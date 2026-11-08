import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:interstellar/src/api/bookmark.dart';
import 'package:interstellar/src/api/client.dart';
import 'package:interstellar/src/controller/server.dart';

final _comment = {
  'comment': {
    'id': 1,
    'path': '0.1',
    'deleted': false,
    'removed': false,
    'content': 'saved',
    'language_id': 0,
    'published': '2026-01-01T00:00:00Z',
    'ap_id': 'https://example.com/comment/1',
  },
  'creator': {
    'id': 2,
    'name': 'user',
    'local': true,
    'actor_id': 'https://example.com/u/user',
    'published': '2026-01-01T00:00:00Z',
    'bot_account': false,
  },
  'community': {
    'id': 3,
    'name': 'community',
    'local': true,
    'actor_id': 'https://example.com/c/community',
  },
  'post': {'id': 4},
  'saved': true,
};

/// Lists saved comments and no saved posts, returning the page requested.
Future<(List<Object>, String?)> _list({
  required bool hasComments,
  String? page,
}) {
  final pages = <String?>[];
  final server = MockClient((request) async {
    final path = request.url.path;
    if (!path.endsWith('/site')) {
      pages.add(request.url.queryParameters['page']);
    }
    final Object body;
    if (path.endsWith('/site')) {
      body = {'all_languages': <Object?>[]};
    } else if (path.endsWith('/post/list')) {
      body = {'posts': <Object?>[]};
    } else if (path.endsWith('/comment/list')) {
      body = {
        'comments': hasComments ? [_comment] : <Object?>[],
      };
    } else {
      fail('unexpected request to $path');
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
      software: ServerSoftware.lemmy,
      domain: 'example.com',
    ),
  );

  return api.list(page: page).then((result) {
    // both lists must be asked for the same page
    expect(pages, [page, page]);
    return result;
  });
}

void main() {
  test('Lemmy bookmarks keep paging while saved comments remain', () async {
    final (items, next) = await _list(hasComments: true, page: '2');

    expect(items, hasLength(1));
    expect(next, '3');
  });

  test('Lemmy bookmarks stop paging when nothing is left', () async {
    final (items, next) = await _list(hasComments: false);

    expect(items, isEmpty);
    expect(next, isNull);
  });
}
