import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:interstellar/src/api/api.dart';
import 'package:interstellar/src/api/client.dart';
import 'package:interstellar/src/api/mastodon.dart';
import 'package:interstellar/src/controller/server.dart';

Map<String, dynamic> _poll({List<int> own = const [], bool voted = false}) => {
  'id': '77',
  'expires_at': '2030-01-01T00:00:00.000Z',
  'expired': false,
  'multiple': true,
  'votes_count': 3,
  'voters_count': 2,
  'voted': voted,
  'own_votes': own,
  'options': [
    {'title': 'Yes', 'votes_count': 2},
    {'title': 'No', 'votes_count': 1},
  ],
};

Map<String, dynamic> _status(Map<String, dynamic>? poll) => {
  'id': '500',
  'created_at': '2026-11-05T17:11:20.089Z',
  'in_reply_to_id': null,
  'sensitive': false,
  'spoiler_text': '',
  'language': 'en',
  'uri': 'https://example.social/users/alice/statuses/500',
  'replies_count': 0,
  'reblogs_count': 0,
  'favourites_count': 0,
  'edited_at': null,
  'content': '<p>Vote</p>',
  'reblog': null,
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
    'uri': 'https://example.social/users/alice',
  },
  'media_attachments': <dynamic>[],
  'card': null,
  'poll': poll,
};

void main() {
  final id = mastodonId('example.social', '500');

  test('a status poll becomes a poll with indexed choices', () {
    final post = mastodonPost(
      _status(_poll(own: [1], voted: true)),
      'example.social',
    );
    final poll = post.poll!;

    expect(poll.postId, id);
    expect(poll.multiple, isTrue);
    expect(poll.endPoll.isAtSameMomentAs(DateTime.utc(2030)), isTrue);
    expect(poll.choices.map((c) => (c.id, c.text, c.numVotes, c.chosen)), [
      (0, 'Yes', 2, false),
      (1, 'No', 1, true),
    ]);
  });

  test('a status without a poll has none', () {
    expect(mastodonPost(_status(null), 'example.social').poll, isNull);
  });

  test(
    'voting sends the chosen indexes to the poll and returns the post',
    () async {
      final requests = <http.Request>[];
      final api = API(
        ServerClient(
          httpClient: MockClient((request) async {
            requests.add(request);
            final key = '${request.method} ${request.url.path}';
            final body = switch (key) {
              'GET /api/v1/statuses/500' => _status(_poll()),
              'POST /api/v1/polls/77/votes' => _poll(own: [1], voted: true),
              _ => null,
            };
            if (body == null) return http.Response('not found: $key', 404);
            return http.Response(jsonEncode(body), 200);
          }),
          software: ServerSoftware.mastodon,
          domain: 'example.social',
        ),
      );
      // the id must be known, as it is once the status has been listed
      mastodonId('example.social', '500');

      final post = await api.threads.votePoll(id, [1]);

      expect(requests.map((r) => '${r.method} ${r.url.path}'), [
        'GET /api/v1/statuses/500',
        'POST /api/v1/polls/77/votes',
      ]);
      expect(jsonDecode(requests[1].body), {
        'choices': ['1'],
      });
      expect(post.poll!.choices[1].chosen, isTrue);
    },
  );

  test('a poll without an end date, hidden counts and no own votes', () {
    final post = mastodonPost(
      _status({
        'id': '77',
        'expires_at': null,
        'expired': false,
        'multiple': false,
        'votes_count': 5,
        'voters_count': 5,
        'voted': false,
        'options': [
          {'title': 'A', 'votes_count': null},
        ],
      }),
      'example.social',
    );
    final poll = post.poll!;

    expect(poll.neverEnds, isTrue);
    expect(poll.multiple, isFalse);
    expect(poll.choices.single.numVotes, 0);
    expect(poll.choices.single.chosen, isFalse);
  });

  test('a poll with an end date does not report that it never ends', () {
    final post = mastodonPost(_status(_poll()), 'example.social');
    expect(post.poll!.neverEnds, isFalse);
  });

  test('a refused vote is an error, not a silent success', () async {
    final api = API(
      ServerClient(
        httpClient: MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response(jsonEncode(_status(_poll())), 200);
          }
          return http.Response('{"error":"Validation failed"}', 422);
        }),
        software: ServerSoftware.mastodon,
        domain: 'example.social',
      ),
    );
    mastodonId('example.social', '500');

    await expectLater(api.threads.votePoll(id, [0]), throwsA(anything));
  });

  test('voting on a post without a poll is an error', () async {
    final api = API(
      ServerClient(
        httpClient: MockClient(
          (request) async => http.Response(jsonEncode(_status(null)), 200),
        ),
        software: ServerSoftware.mastodon,
        domain: 'example.social',
      ),
    );
    mastodonId('example.social', '500');

    await expectLater(api.threads.votePoll(id, [0]), throwsStateError);
  });
}
