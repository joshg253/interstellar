import 'package:flutter_test/flutter_test.dart';
import 'package:interstellar/src/api/mastodon.dart';
import 'package:interstellar/src/models/post.dart';

Map<String, dynamic> account(String id, String acct) => {
  'id': id,
  'username': acct.split('@').first,
  'acct': acct,
  'display_name': 'Name of ${acct.split('@').first}',
  'bot': false,
  'note': '<p>About me</p>',
  'avatar': 'https://cdn.example.com/a.png',
  'header': 'https://cdn.example.com/h.png',
  'created_at': '2022-12-20T00:00:00.000Z',
  'followers_count': 12,
  'url': 'https://social.example.com/@${acct.split('@').first}',
  'uri': 'https://social.example.com/users/${acct.split('@').first}',
};

Map<String, dynamic> status(
  String id, {
  String? inReplyTo,
  String acct = 'alice',
  Map<String, dynamic>? reblog,
  String content = '<p>Hello</p>',
  List<Map<String, dynamic>> media = const [],
}) => {
  'id': id,
  'created_at': '2026-11-05T17:11:20.089Z',
  'in_reply_to_id': inReplyTo,
  'sensitive': false,
  'spoiler_text': '',
  'visibility': 'public',
  'language': 'en',
  'uri': 'https://social.example.com/users/alice/statuses/$id',
  'url': 'https://social.example.com/@alice/$id',
  'replies_count': 3,
  'reblogs_count': 5,
  'favourites_count': 9,
  'edited_at': null,
  'content': content,
  'reblog': reblog,
  'favourited': true,
  'reblogged': false,
  'account': account('1001', acct),
  'media_attachments': media,
  'card': null,
  'poll': null,
};

void main() {
  group('ids', () {
    test('are stable, distinct, and exact as JS numbers', () {
      final a = mastodonId('social.example.com', '117564943898337275');
      final b = mastodonId('social.example.com', '117564943898337276');
      final c = mastodonId('other.example.com', '117564943898337275');
      expect(a, mastodonId('social.example.com', '117564943898337275'));
      expect({a, b, c}, hasLength(3));
      for (final id in [a, b, c]) {
        expect(id, greaterThanOrEqualTo(0));
        expect(id, lessThan(9007199254740992)); // 2^53
      }
    });

    test('map back to the original string id', () {
      final id = mastodonId('social.example.com', '117564943898337275');
      expect(mastodonRawId(id), '117564943898337275');
    });
  });

  group('html', () {
    test('becomes markdown', () {
      expect(
        mastodonHtmlToMarkdown(
          '<p>Hello <a href="https://social.example.com/tags/news" '
          'class="mention hashtag">#<span>news</span></a><br>line two</p> '
          '<p>Second &amp; last</p>',
        ),
        'Hello [#news](https://social.example.com/tags/news)  \nline two\n\n'
        'Second & last',
      );
    });
  });

  group('post', () {
    test('maps a status', () {
      final post = mastodonPost(
        status('117564943898337275'),
        'social.example.com',
      );
      expect(post.type, PostType.microblog);
      expect(post.id, mastodonId('social.example.com', '117564943898337275'));
      expect(post.body, 'Hello');
      expect(post.numComments, 3);
      expect(post.upvotes, 9);
      expect(post.boosts, 5);
      expect(post.myVote, 1);
      expect(post.user.name, 'alice');
      expect(post.community.name, 'social.example.com');
      expect(
        post.apId,
        'https://social.example.com/users/alice/statuses/117564943898337275',
      );
    });

    test('a boost shows the boosted status', () {
      final original = status('2002', acct: 'bob@other.example.com');
      final post = mastodonPost(
        status('3003', reblog: original),
        'social.example.com',
      );
      expect(post.id, mastodonId('social.example.com', '2002'));
      expect(post.user.name, 'bob@other.example.com');
    });

    test('takes the first image attachment', () {
      final post = mastodonPost(
        status(
          '4004',
          media: [
            {
              'type': 'image',
              'url': 'https://cdn.example.com/m.jpeg',
              'description': 'a cat',
              'blurhash': 'LEHV6nWB2yk8pyo0adR*.7kCMdnj',
              'meta': {
                'original': {'width': 100, 'height': 50},
              },
            },
          ],
        ),
        'social.example.com',
      );
      expect(post.image?.src, 'https://cdn.example.com/m.jpeg');
      expect(post.image?.altText, 'a cat');
    });
  });

  group('comments', () {
    test('context becomes a reply tree', () {
      final root = status('100');
      final tree = mastodonCommentTree(
        {
          'ancestors': <dynamic>[],
          'descendants': [
            status('101', inReplyTo: '100', acct: 'bob@other.example.com'),
            status('102', inReplyTo: '101'),
            status('103', inReplyTo: '100'),
          ],
        },
        root,
        'social.example.com',
      );
      expect(tree.map((c) => c.id), [
        mastodonId('social.example.com', '101'),
        mastodonId('social.example.com', '103'),
      ]);
      final first = tree.first;
      expect(first.postId, mastodonId('social.example.com', '100'));
      expect(first.parentId, mastodonId('social.example.com', '100'));
      expect(first.childCount, 1);
      expect(
        first.children!.single.id,
        mastodonId('social.example.com', '102'),
      );
      expect(first.children!.single.parentId, first.id);
      expect(tree.last.children, isEmpty);
    });
  });
}
