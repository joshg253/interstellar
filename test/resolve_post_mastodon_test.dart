import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:interstellar/src/api/client.dart';
import 'package:interstellar/src/api/resolve.dart';
import 'package:interstellar/src/controller/server.dart';

Map<String, Object?> _status(String uri) => {
  'id': '500',
  'created_at': '2026-11-05T17:11:20.089Z',
  'in_reply_to_id': null,
  'sensitive': false,
  'spoiler_text': '',
  'language': 'en',
  'uri': uri,
  'url': uri,
  'replies_count': 0,
  'reblogs_count': 0,
  'favourites_count': 0,
  'edited_at': null,
  'content': '<p>Hello</p>',
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
    'uri': 'https://social.example.com/users/alice',
  },
  'media_attachments': <Object?>[],
  'card': null,
  'poll': null,
};

ServerClient _client(List<Object?> statuses) => ServerClient(
  httpClient: MockClient(
    (request) async => http.Response(jsonEncode({'statuses': statuses}), 200),
  ),
  software: ServerSoftware.mastodon,
  domain: 'social.example.com',
);

void main() {
  const asked = 'https://other.example.com/users/bob/statuses/9';

  test('mastodon: finds the status that was asked for', () async {
    final found = await resolvePost(_client([_status(asked)]), asked);

    expect(found, isNotNull);
    expect(found!.apId, asked);
  });

  test('mastodon: a search fallback to another status is not a copy', () async {
    final found = await resolvePost(
      _client([_status('https://other.example.com/users/bob/statuses/10')]),
      asked,
    );

    expect(found, isNull);
  });
}
