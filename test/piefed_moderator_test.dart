import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:interstellar/src/api/client.dart';
import 'package:interstellar/src/api/community_moderation.dart';
import 'package:interstellar/src/controller/server.dart';

void main() {
  for (final added in [true, false]) {
    test(
      'PieFed updateModerator added=$added posts the spec body and reads the list back',
      () async {
        final requests = <http.Request>[];
        final client = ServerClient(
          httpClient: MockClient((request) async {
            requests.add(request);
            if (request.method == 'POST') {
              return http.Response('{"moderators": []}', 200);
            }
            if (request.method != 'GET') return http.Response('{}', 404);
            return http.Response(
              jsonEncode({
                'community_view': {
                  'community': {
                    'id': 7,
                    'name': 'test',
                    'title': 'Test',
                    'local': true,
                    'nsfw': false,
                    'restricted_to_mods': false,
                    'actor_id': 'https://example.com/c/test',
                  },
                  'counts': {
                    'subscriptions_count': 0,
                    'post_count': 0,
                    'post_reply_count': 0,
                  },
                  'subscribed': 'NotSubscribed',
                },
                'moderators': [
                  {
                    'moderator': {
                      'id': 9,
                      'user_name': 'mod',
                      'local': true,
                      'bot': false,
                      'published': '2025-01-01T00:00:00Z',
                      'actor_id': 'https://example.com/u/mod',
                    },
                  },
                ],
              }),
              200,
            );
          }),
          software: ServerSoftware.piefed,
          domain: 'example.com',
        );

        final mods = await APICommunityModeration(
          client,
        ).updateModerator(7, 9, added);

        expect(requests.first.method, 'POST');
        expect(requests.first.url.path, endsWith('/community/mod'));
        expect(jsonDecode(requests.first.body), {
          'community_id': 7,
          'person_id': 9,
          'added': added,
        });
        expect(requests.length, 2);
        expect(requests[1].method, 'GET');
        expect(requests[1].url.path, endsWith('/community'));
        expect(requests[1].url.queryParameters, {'id': '7'});
        expect(mods.map((m) => m.id), [9]);
      },
    );
  }
}
