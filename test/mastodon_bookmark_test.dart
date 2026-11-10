import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:interstellar/src/api/api.dart';
import 'package:interstellar/src/api/bookmark.dart';
import 'package:interstellar/src/api/client.dart';
import 'package:interstellar/src/api/mastodon.dart';
import 'package:interstellar/src/controller/server.dart';
import 'package:interstellar/src/models/post.dart';

Map<String, dynamic> _status(String id, {bool bookmarked = false}) => {
  'id': id,
  'created_at': '2026-11-05T17:11:20.089Z',
  'in_reply_to_id': null,
  'sensitive': false,
  'spoiler_text': '',
  'language': 'en',
  'uri': 'https://example.social/users/alice/statuses/$id',
  'replies_count': 0,
  'reblogs_count': 0,
  'favourites_count': 0,
  'edited_at': null,
  'content': '<p>Hello</p>',
  'reblog': null,
  'favourited': false,
  'reblogged': false,
  'bookmarked': bookmarked,
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
    'uri': 'https://example.social/users/alice',
  },
  'media_attachments': <dynamic>[],
  'card': null,
  'poll': null,
};

API _api(http.Response Function(http.Request) handler, List<String> calls) =>
    API(
      ServerClient(
        httpClient: MockClient((request) async {
          calls.add('${request.method} ${request.url}');
          return handler(request);
        }),
        software: ServerSoftware.mastodon,
        domain: 'example.social',
      ),
    );

void main() {
  final id = mastodonId('example.social', '500');

  test('a bookmarked status is marked as saved', () {
    expect(
      mastodonPost(
        _status('500', bookmarked: true),
        'example.social',
      ).bookmarks,
      [''],
    );
    expect(mastodonPost(_status('500'), 'example.social').bookmarks, isEmpty);
  });

  test('bookmarking and unbookmarking', () async {
    final calls = <String>[];
    final api = _api(
      (r) => http.Response(
        jsonEncode(
          _status('500', bookmarked: r.url.path.endsWith('/bookmark')),
        ),
        200,
      ),
      calls,
    );

    final added = await api.bookmark.addBookmarkToDefault(
      subjectType: BookmarkListSubject.microblog,
      subjectId: id,
    );
    final removed = await api.bookmark.removeBookmarkFromAll(
      subjectType: BookmarkListSubject.microblog,
      subjectId: id,
    );

    expect(calls, [
      'POST https://example.social/api/v1/statuses/500/bookmark',
      'POST https://example.social/api/v1/statuses/500/unbookmark',
    ]);
    expect(added, ['']);
    expect(removed, isEmpty);
  });

  test('the bookmark list pages by the Link header, not by status id', () async {
    final calls = <String>[];
    final api = _api(
      (r) => http.Response(
        jsonEncode([_status('500', bookmarked: true)]),
        200,
        headers: {
          'link':
              '<https://example.social/api/v1/bookmarks?max_id=77>; rel="next", '
              '<https://example.social/api/v1/bookmarks?min_id=99>; rel="prev"',
        },
      ),
      calls,
    );

    final (items, next) = await api.bookmark.list(page: '12');

    expect(calls.single, contains('max_id=12'));
    expect(items.single, isA<PostModel>());
    expect(next, '77');
  });

  test('no next link means no more pages', () async {
    final api = _api(
      (r) => http.Response(jsonEncode([_status('500')]), 200),
      [],
    );

    final (_, next) = await api.bookmark.list();

    expect(next, isNull);
  });
}
