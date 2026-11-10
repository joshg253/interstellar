import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:interstellar/src/api/api.dart';
import 'package:interstellar/src/api/client.dart';
import 'package:interstellar/src/api/mastodon.dart';
import 'package:interstellar/src/controller/server.dart';
import 'package:interstellar/src/models/post.dart';

Map<String, dynamic> _status(
  String id, {
  bool favourited = false,
  bool reblogged = false,
  String? inReplyTo,
}) => {
  'id': id,
  'created_at': '2026-11-05T17:11:20.089Z',
  'in_reply_to_id': inReplyTo,
  'sensitive': false,
  'spoiler_text': '',
  'language': 'en',
  'uri': 'https://example.social/users/alice/statuses/$id',
  'replies_count': 0,
  'reblogs_count': reblogged ? 1 : 0,
  'favourites_count': favourited ? 1 : 0,
  'edited_at': null,
  'content': '<p>Hello</p>',
  'reblog': null,
  'favourited': favourited,
  'reblogged': reblogged,
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

class _Rig {
  _Rig(Map<String, Map<String, dynamic>> routes) {
    api = API(
      ServerClient(
        httpClient: MockClient((request) async {
          requests.add(request);
          final key = '${request.method} ${request.url.path}';
          final body = routes[key];
          if (body == null) return http.Response('not found: $key', 404);
          return http.Response(jsonEncode(body), 200);
        }),
        software: ServerSoftware.mastodon,
        domain: 'example.social',
      ),
    );
  }

  late final API api;
  final requests = <http.Request>[];

  List<String> get calls =>
      requests.map((r) => '${r.method} ${r.url.path}').toList();

  Map<String, dynamic> bodyOf(int i) =>
      jsonDecode(requests[i].body) as Map<String, dynamic>;
}

void main() {
  final id = mastodonId('example.social', '500');

  test('favoriting an unfavorited status favorites it', () async {
    final rig = _Rig({
      'GET /api/v1/statuses/500': _status('500'),
      'POST /api/v1/statuses/500/favourite': _status('500', favourited: true),
    });

    final post = await rig.api.microblogs.putFavorite(id);

    expect(rig.calls, [
      'GET /api/v1/statuses/500',
      'POST /api/v1/statuses/500/favourite',
    ]);
    expect(post.myVote, 1);
  });

  test('favoriting a favorited status unfavorites it', () async {
    final rig = _Rig({
      'GET /api/v1/statuses/500': _status('500', favourited: true),
      'POST /api/v1/statuses/500/unfavourite': _status('500'),
    });

    final post = await rig.api.microblogs.putFavorite(id);

    expect(rig.calls.last, 'POST /api/v1/statuses/500/unfavourite');
    expect(post.myVote, 0);
  });

  test('boosting toggles reblog', () async {
    final rig = _Rig({
      'GET /api/v1/statuses/500': _status('500'),
      'POST /api/v1/statuses/500/reblog': {
        ..._status('900'),
        'reblog': _status('500', reblogged: true),
      },
    });

    final post = await rig.api.microblogs.putVote(id, 1);

    expect(rig.calls.last, 'POST /api/v1/statuses/500/reblog');
    expect(post.myBoost, true);
    expect(post.id, id);
  });

  test('creating a post sends the text and language', () async {
    final rig = _Rig({'POST /api/v1/statuses': _status('501')});

    final post = await rig.api.microblogs.create(
      0,
      body: 'Hi there',
      lang: 'en',
      isAdult: true,
    );

    final body = rig.bodyOf(0);
    expect(body['status'], 'Hi there');
    expect(body['language'], 'en');
    expect(body['sensitive'], true);
    expect(post.type, PostType.microblog);
  });

  test('a downvote does not boost', () async {
    final rig = _Rig({});

    await expectLater(
      rig.api.microblogs.putVote(id, -1),
      throwsA(isA<UnsupportedError>()),
    );
    expect(rig.calls, isEmpty);
  });

  test('a reply with an image is refused, not sent without it', () async {
    final rig = _Rig({});

    await expectLater(
      rig.api.comments.create(
        PostType.microblog,
        id,
        'x',
        lang: 'en',
        image: XFile('a.png'),
      ),
      throwsA(isA<UnsupportedError>()),
    );
    expect(rig.calls, isEmpty);
  });

  test('editing is refused until the source text is loaded', () async {
    final rig = _Rig({});

    await expectLater(
      rig.api.microblogs.edit(id, 'Changed', 'en', false),
      throwsA(isA<UnsupportedError>()),
    );
    expect(rig.calls, isEmpty);
  });

  test('deleting a post sends DELETE', () async {
    final rig = _Rig({'DELETE /api/v1/statuses/500': _status('500')});

    await rig.api.microblogs.delete(id);

    expect(rig.calls, ['DELETE /api/v1/statuses/500']);
  });

  test('reporting looks up the author and sends the status', () async {
    final rig = _Rig({
      'GET /api/v1/statuses/500': _status('500'),
      'POST /api/v1/reports': <String, dynamic>{},
    });

    await rig.api.microblogs.report(id, 'spam');

    final body = rig.bodyOf(1);
    expect(body['account_id'], '1001');
    expect(body['status_ids'], ['500']);
    expect(body['comment'], 'spam');
  });

  test('replying posts with in_reply_to_id', () async {
    final rig = _Rig({
      'POST /api/v1/statuses': _status('502', inReplyTo: '500'),
    });

    final comment = await rig.api.comments.create(
      PostType.microblog,
      id,
      'A reply',
      lang: 'en',
    );

    expect(rig.bodyOf(0)['in_reply_to_id'], '500');
    expect(rig.bodyOf(0)['status'], 'A reply');
    expect(comment.body, 'Hello');
  });

  test('replying to a comment targets that comment', () async {
    final rig = _Rig({
      'POST /api/v1/statuses': _status('503', inReplyTo: '502'),
    });
    final parent = mastodonId('example.social', '502');

    await rig.api.comments.create(
      PostType.microblog,
      id,
      'Nested',
      lang: 'en',
      parentCommentId: parent,
    );

    expect(rig.bodyOf(0)['in_reply_to_id'], '502');
  });

  test('favoriting a comment toggles like a post', () async {
    final rig = _Rig({
      'GET /api/v1/statuses/502': _status('502'),
      'POST /api/v1/statuses/502/favourite': _status('502', favourited: true),
    });

    final comment = await rig.api.comments.vote(
      PostType.microblog,
      mastodonId('example.social', '502'),
      1,
      1,
    );

    expect(rig.calls.last, 'POST /api/v1/statuses/502/favourite');
    expect(comment.myVote, 1);
  });

  test('downvoting is not supported', () {
    final rig = _Rig({});

    expect(
      () => rig.api.comments.vote(PostType.microblog, id, -1, -1),
      throwsA(isA<UnsupportedError>()),
    );
  });
}
