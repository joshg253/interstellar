import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:interstellar/src/api/client.dart';
import 'package:interstellar/src/api/resolve.dart';
import 'package:interstellar/src/controller/server.dart';

ServerClient _client(ServerSoftware software, MockClient server) =>
    ServerClient(httpClient: server, software: software, domain: 'example.com');

Map<String, Object?> _community() => {
  'community': {
    'id': 7,
    'name': 'test',
    'title': 'test',
    'local': false,
    'actor_id': 'https://other.example/c/test',
    'nsfw': false,
    'posting_restricted_to_mods': false,
    'restricted_to_mods': false,
  },
  'counts': {
    'subscribers': 1,
    'subscriptions_count': 1,
    'posts': 0,
    'post_count': 0,
    'comments': 0,
    'post_reply_count': 0,
  },
  'subscribed': 'NotSubscribed',
};

void main() {
  for (final software in [ServerSoftware.lemmy, ServerSoftware.piefed]) {
    test('${software.name}: resolves a remote community by its id', () async {
      late Uri asked;
      final server = MockClient((request) async {
        asked = request.url;
        return http.Response(
          jsonEncode({'community': _community()}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final found = await resolveCommunity(
        _client(software, server),
        'https://other.example/c/test',
      );

      expect(asked.path, endsWith('/resolve_object'));
      expect(asked.queryParameters['q'], 'https://other.example/c/test');
      expect(found?.id, 7);
      expect(found?.name, 'test@other.example');
    });

    test('${software.name}: null when the server has no community', () async {
      final server = MockClient(
        (_) async => http.Response(
          jsonEncode(<String, Object?>{}),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );

      expect(
        await resolveCommunity(_client(software, server), 'https://x/c/y'),
        isNull,
      );
    });
  }
}
