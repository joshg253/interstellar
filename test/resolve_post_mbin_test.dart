import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:interstellar/src/api/client.dart';
import 'package:interstellar/src/api/resolve.dart';
import 'package:interstellar/src/controller/server.dart';

ServerClient _client(MockClient server) => ServerClient(
  httpClient: server,
  software: ServerSoftware.mbin,
  domain: 'mbin.example',
);

Map<String, Object?> _entry() => {
  'entryId': 77,
  'apId': 'https://other.example/post/5',
  'user': {
    'userId': 3,
    'username': 'someone',
    'isBot': false,
    'createdAt': '2024-01-01T00:00:00+00:00',
  },
  'magazine': {'magazineId': 9, 'name': 'test@other.example'},
  'title': 'a thread',
  'lang': 'en',
  'numComments': 0,
  'isOc': false,
  'isAdult': false,
  'isPinned': false,
  'isLocked': false,
  'createdAt': '2026-11-06T00:00:00+00:00',
  'lastActive': '2026-11-06T00:00:00+00:00',
  'visibility': 'visible',
};

MockClient _search(Map<String, Object?> body, void Function(Uri) seen) =>
    MockClient((request) async {
      seen(request.url);
      return http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

void main() {
  test('mbin: finds a remote thread by its id through search', () async {
    late Uri asked;
    final server = _search({
      'items': <Object?>[],
      'apObjects': [_entry()],
    }, (u) => asked = u);

    final found = await resolvePost(
      _client(server),
      'https://other.example/post/5',
    );

    expect(found, isNotNull);
    expect(found!.id, 77);
    expect(found.apId, 'https://other.example/post/5');
    expect(asked.path, '/api/search');
    expect(asked.queryParameters['q'], 'https://other.example/post/5');
  });

  test('mbin: a comment is not a post', () async {
    final comment = {..._entry(), 'commentId': 5};
    final server = _search({
      'apObjects': [comment],
    }, (_) {});

    expect(
      await resolvePost(_client(server), 'https://other.example/post/5'),
      isNull,
    );
  });

  test('mbin: an object that is not the one asked for is not a copy', () async {
    final server = _search({
      'apObjects': [
        {..._entry(), 'apId': 'https://other.example/post/6'},
      ],
    }, (_) {});

    expect(
      await resolvePost(_client(server), 'https://other.example/post/5'),
      isNull,
    );
  });

  test('mbin: null when the server knows nothing of it', () async {
    final server = _search({'apObjects': <Object?>[]}, (_) {});

    expect(
      await resolvePost(_client(server), 'https://other.example/post/5'),
      isNull,
    );
  });
}
