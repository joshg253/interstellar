import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:interstellar/src/api/client.dart';
import 'package:interstellar/src/api/feed_source.dart';
import 'package:interstellar/src/api/mastodon.dart';
import 'package:interstellar/src/controller/server.dart';

const _host = 'social.example.com';

Map<String, dynamic> _status(
  String id, {
  String content = '<p>Hello</p>',
  String spoiler = '',
  List<Map<String, dynamic>> media = const [],
  Map<String, dynamic>? card,
  Map<String, dynamic>? reblog,
}) => {
  'id': id,
  'created_at': '2026-11-05T17:11:20.089Z',
  'in_reply_to_id': null,
  'sensitive': false,
  'spoiler_text': spoiler,
  'language': 'en',
  'uri': 'https://$_host/users/alice/statuses/$id',
  'replies_count': 0,
  'reblogs_count': 0,
  'favourites_count': 0,
  'edited_at': null,
  'content': content,
  'reblog': reblog,
  'favourited': false,
  'reblogged': false,
  'account': {
    'id': '1001',
    'acct': 'alice',
    'display_name': 'Alice',
    'bot': false,
    'note': '',
    'avatar': '',
    'header': '',
    'created_at': '2022-12-20T00:00:00.000Z',
    'followers_count': 1,
    'uri': 'https://$_host/users/alice',
  },
  'media_attachments': media,
  'card': card,
  'poll': null,
};

ServerClient _client(http.Response Function(http.Request) handler) =>
    ServerClient(
      httpClient: MockClient((request) async => handler(request)),
      software: ServerSoftware.mastodon,
      domain: _host,
    );

void main() {
  group('html to markdown', () {
    test('text that looks like markdown stays literal', () {
      expect(
        mastodonHtmlToMarkdown(
          '<p>![](https://t.example.com/p.png) and *bold* [x](http://y)</p>',
        ),
        r'!\[\](https://t.example.com/p.png) and \*bold\* \[x\](http://y)',
      );
    });

    test('markdown block syntax at the start of a line is escaped', () {
      expect(
        mastodonHtmlToMarkdown(
          '<p># no heading</p><p>- no list</p><p>> no quote</p> '
          '<p>::: spoiler x</p>',
        ),
        '\\# no heading\n\n\\- no list\n\n\\> no quote\n\n\\::: spoiler x',
      );
    });

    test('link text and href are made safe', () {
      expect(
        mastodonHtmlToMarkdown('<a href="https://x.example.com/a)b">te]xt</a>'),
        r'[te\]xt](https://x.example.com/a%29b)',
      );
    });

    test('links that are not http(s) are dropped but their text stays', () {
      expect(
        mastodonHtmlToMarkdown('<a href="javascript:alert(1)">click</a>'),
        'click',
      );
    });

    test('tags are case-insensitive and hrefs may be single-quoted', () {
      expect(
        mastodonHtmlToMarkdown("<A HREF='https://x.example.com/p'>t</A>"),
        '[t](https://x.example.com/p)',
      );
    });

    test('a line break is a hard break', () {
      expect(mastodonHtmlToMarkdown('<p>a<br>b</p>'), 'a  \nb');
    });

    test('numeric entities are decoded', () {
      expect(
        mastodonHtmlToMarkdown('<p>it&#8217;s &#x27;ok&#x27; &amp;lt;</p>'),
        "it’s 'ok' &lt;",
      );
    });
  });

  group('post', () {
    test('a link card title cannot inject markup', () {
      final post = mastodonPost(
        _status(
          '1',
          card: {
            'url': 'https://example.com/card',
            'title': 'x](https://evil.example.com) ![',
          },
        ),
        _host,
      );

      expect(
        post.body,
        endsWith(
          r'[x\](https://evil.example.com) !\[](https://example.com/card)',
        ),
      );
    });

    test('a content warning hides the text in a spoiler', () {
      final post = mastodonPost(
        _status('1', spoiler: 'Politics', content: '<p>Body</p>'),
        _host,
      );

      expect(post.body, '::: spoiler Politics\nBody\n:::');
    });

    test('an attachment with no url is skipped instead of failing', () {
      final post = mastodonPost(
        _status(
          '1',
          media: [
            {'type': 'image', 'url': null, 'remote_url': null},
          ],
        ),
        _host,
      );

      expect(post.image, isNull);
    });

    test('an attachment falls back to its remote url', () {
      final post = mastodonPost(
        _status(
          '1',
          media: [
            {
              'type': 'image',
              'url': null,
              'remote_url': 'https://cdn.example.com/a.png',
            },
          ],
        ),
        _host,
      );

      expect(post.image!.src, 'https://cdn.example.com/a.png');
    });

    test('an image with a non-web url is ignored', () {
      final post = mastodonPost(
        _status(
          '1',
          media: [
            {'type': 'image', 'url': 'javascript:alert(1)'},
          ],
        ),
        _host,
      );

      expect(post.image, isNull);
    });
  });

  group('timeline', () {
    http.Response trending(http.Request r) =>
        http.Response(jsonEncode([_status('9')]), 200);

    test(
      'local falls back to trending only when the server refuses guests',
      () async {
        final api = MastodonAPI(
          _client(
            (r) => r.url.path.endsWith('/timelines/public')
                ? http.Response('{"error":"forbidden"}', 403)
                : trending(r),
          ),
        );

        final list = await api.timeline(FeedSource.local);

        expect(list.items.single.apId, endsWith('/9'));
      },
    );

    test('local does not hide a server error behind trending', () async {
      final api = MastodonAPI(
        _client(
          (r) => r.url.path.endsWith('/timelines/public')
              ? http.Response('boom', 500)
              : trending(r),
        ),
      );

      expect(() => api.timeline(FeedSource.local), throwsA(isA<Exception>()));
    });

    test('a boost and its original on one page appear once', () async {
      final original = _status('1');
      final api = MastodonAPI(
        _client(
          (r) => http.Response(
            jsonEncode([_status('7', reblog: original), original]),
            200,
          ),
        ),
      );

      final list = await api.timeline(FeedSource.all);

      expect(list.items, hasLength(1));
    });
  });
}
