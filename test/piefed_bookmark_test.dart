import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:interstellar/src/api/bookmark.dart';
import 'package:interstellar/src/api/client.dart';
import 'package:interstellar/src/controller/server.dart';

void main() {
  test('PieFed bookmarks ask for saved posts and comments', () async {
    final saved = <String>[];
    final server = MockClient((request) async {
      final path = request.url.path;
      Object body;
      if (path.endsWith('/site')) {
        body = {
          'site': {'all_languages': <Object?>[]},
        };
      } else {
        if (request.url.queryParameters['saved_only'] == 'true') {
          saved.add(path);
        }
        body = path.endsWith('/post/list')
            ? {'posts': <Object?>[]}
            : {'comments': <Object?>[], 'next_page': '2'};
      }
      return http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final api = APIBookmark(
      ServerClient(
        httpClient: server,
        software: ServerSoftware.piefed,
        domain: 'example.com',
      ),
    );

    final (items, next) = await api.list();

    expect(items, isEmpty);
    // saved posts end here but saved comments go on
    expect(next, '2');
    expect(
      saved,
      unorderedEquals(['/api/alpha/post/list', '/api/alpha/comment/list']),
    );
  });
}
