import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:interstellar/src/api/client.dart';
import 'package:interstellar/src/api/search.dart';
import 'package:interstellar/src/controller/server.dart';
import 'package:interstellar/src/screens/explore/explore_screen.dart';

void main() {
  for (final software in [ServerSoftware.lemmy, ServerSoftware.piefed]) {
    test('${software.name} search sends the Local filter', () async {
      final listingTypes = <String?>[];
      final server = MockClient((request) async {
        final path = request.url.path;
        Object body;
        if (path.endsWith('/site')) {
          // Lemmy lists languages at the top level, PieFed under `site`
          body = {
            'all_languages': <Object?>[],
            'site': {'all_languages': <Object?>[]},
          };
        } else {
          listingTypes.add(request.url.queryParameters['listing_type']);
          body = {
            'posts': <Object?>[],
            'comments': <Object?>[],
            'communities': <Object?>[],
            'users': <Object?>[],
          };
        }
        return http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = APISearch(
        ServerClient(
          httpClient: server,
          software: software,
          domain: 'example.com',
        ),
      );
      await api.get(search: 'q', filter: ExploreFilter.local);
      await api.get(search: 'q', filter: ExploreFilter.all);
      await api.get(search: 'q');

      expect(listingTypes, ['Local', 'All', 'All']);
    });
  }
}
