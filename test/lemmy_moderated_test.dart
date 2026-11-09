import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:interstellar/src/api/client.dart';
import 'package:interstellar/src/api/community.dart';
import 'package:interstellar/src/controller/server.dart';
import 'package:interstellar/src/screens/explore/explore_screen.dart';

Map<String, Object?> _view(int id, String name) => {
  'community_view': {
    'community': {
      'id': id,
      'name': name,
      'title': name,
      'local': true,
      'actor_id': 'https://example.com/c/$name',
      'nsfw': false,
      'posting_restricted_to_mods': false,
    },
    'counts': {'subscribers': 1, 'posts': 0, 'comments': 0},
    'subscribed': 'NotSubscribed',
  },
  'moderators': <Object?>[],
};

void main() {
  for (final site in <Map<String, Object?>>[
    {},
    {'my_user': null},
    {
      'my_user': {'moderates': <Object?>[]},
    },
  ]) {
    test('Lemmy moderated filter is empty for ${jsonEncode(site)}', () async {
      final api = APICommunity(
        ServerClient(
          httpClient: MockClient(
            (request) async => http.Response(
              jsonEncode(site),
              200,
              headers: {'content-type': 'application/json'},
            ),
          ),
          software: ServerSoftware.lemmy,
          domain: 'example.com',
        ),
      );

      final result = await api.list(filter: ExploreFilter.moderated);

      expect(result.items, isEmpty);
    });
  }

  test('Lemmy moderated filter fetches every community in order', () async {
    final api = APICommunity(
      ServerClient(
        httpClient: MockClient((request) async {
          final Object body;
          if (request.url.path.endsWith('/site')) {
            body = {
              'my_user': {
                'moderates': [
                  for (var i = 1; i <= 25; i++)
                    {
                      'community': {'id': i},
                    },
                ],
              },
            };
          } else {
            final id = int.parse(request.url.queryParameters['id']!);
            body = _view(id, 'c');
          }
          return http.Response(
            jsonEncode(body),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
        software: ServerSoftware.lemmy,
        domain: 'example.com',
      ),
    );

    final result = await api.list(filter: ExploreFilter.moderated);

    expect(result.items.map((c) => c.name), [
      for (var i = 1; i <= 25; i++) 'c',
    ]);
  });

  test(
    'Lemmy moderated filter lists only communities the user moderates',
    () async {
      // A server that ignores `type_=ModeratorView` on the list endpoint, as
      // some Lemmy 0.19 instances do, and returns every community.
      final server = MockClient((request) async {
        final path = request.url.path;
        Object body;
        if (path.endsWith('/site')) {
          body = {
            'my_user': {
              'moderates': [
                {
                  'community': {'id': 2},
                },
              ],
            },
          };
        } else if (path.endsWith('/community/list')) {
          body = {
            'communities': [
              _view(1, 'other')['community_view'],
              _view(2, 'mine')['community_view'],
              _view(3, 'another')['community_view'],
            ],
          };
        } else if (path.endsWith('/community')) {
          final id = int.parse(request.url.queryParameters['id']!);
          body = _view(id, id == 2 ? 'mine' : 'other');
        } else {
          return http.Response('{}', 404);
        }
        return http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = APICommunity(
        ServerClient(
          httpClient: server,
          software: ServerSoftware.lemmy,
          domain: 'example.com',
        ),
      );

      final result = await api.list(filter: ExploreFilter.moderated);

      expect(result.items.map((c) => c.name), ['mine']);
    },
  );
}
