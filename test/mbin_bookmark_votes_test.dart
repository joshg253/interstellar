import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:interstellar/src/api/bookmark.dart';
import 'package:interstellar/src/api/client.dart';
import 'package:interstellar/src/controller/server.dart';
import 'package:interstellar/src/models/post.dart';

Map<String, dynamic> _entry(
  int id, {
  Object? favourited,
  Object? userVote,
  int? favourites,
}) => {
  'itemType': 'entry',
  'entryId': id,
  'user': {
    'userId': 1,
    'username': 'alice',
    'createdAt': '2026-01-01T00:00:00+00:00',
    'isBot': false,
  },
  'magazine': {'magazineId': 2, 'name': 'news'},
  'domain': null,
  'title': 'Entry $id',
  'type': 'article',
  'image': null,
  'body': null,
  'lang': 'en',
  'numComments': 0,
  'favourites': favourites ?? 3,
  'dv': 0,
  'uv': 0,
  'isFavourited': favourited,
  'userVote': userVote,
  'isOc': false,
  'isAdult': false,
  'isPinned': false,
  'isLocked': false,
  'createdAt': '2026-01-01T00:00:00+00:00',
  'lastActive': '2026-01-01T00:00:00+00:00',
  'visibility': 'visible',
  'bookmarks': <String>[],
};

Map<String, dynamic> _comment(int id, String type) => {
  ..._entry(id),
  'itemType': type,
  'commentId': id,
  'children': <Object?>[],
  'childCount': 0,
};

APIBookmark _api(http.Response Function(http.Request) handler) => APIBookmark(
  ServerClient(
    httpClient: MockClient((r) async => handler(r)),
    software: ServerSoftware.mbin,
    domain: 'mbin.example.com',
  ),
);

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> _page(List<Map<String, dynamic>> items) => {
  'items': items,
  'pagination': {'currentPage': 1, 'maxPage': 1},
};

void main() {
  test('a bookmark whose vote Mbin left out shows the vote you cast', () async {
    final api = _api(
      (r) => r.url.path.endsWith('/bookmark-lists/show')
          ? _json(_page([_entry(5)]))
          : _json(_entry(5, favourited: true)),
    );

    final (items, _) = await api.list();

    expect((items.single as PostModel).myVote, 1);
  });

  test(
    'with ownVotes off, nothing is fetched until withOwnVote asks',
    () async {
      final paths = <String>[];
      final api = _api((r) {
        paths.add(r.url.path);
        return r.url.path.endsWith('/bookmark-lists/show')
            ? _json(_page([_entry(5), _comment(7, 'entry_comment')]))
            : _json(_entry(5, userVote: 1, favourited: false));
      });

      final (items, _) = await api.list(ownVotes: false);
      expect(paths, hasLength(1));
      expect((items.first as PostModel).myBoost, isFalse);

      final fresh = await api.withOwnVote(items.first) as PostModel;
      expect(fresh.myBoost, isTrue);
      expect(paths.last, endsWith('/entry/5'));
    },
  );

  test('a bookmark that carries its vote is not fetched again', () async {
    final paths = <String>[];
    final api = _api((r) {
      paths.add(r.url.path);
      return _json(_page([_entry(5, favourited: false, userVote: -1)]));
    });

    final (items, _) = await api.list();

    expect((items.single as PostModel).myVote, -1);
    expect(paths, hasLength(1));
  });

  test('a bookmark that cannot be fetched again is still listed', () async {
    final api = _api(
      (r) => r.url.path.endsWith('/bookmark-lists/show')
          ? _json(_page([_entry(5)]))
          : http.Response('gone', 404),
    );

    final (items, _) = await api.list();

    expect((items.single as PostModel).myVote, 0);
  });

  test('each kind of bookmark is fetched from its own endpoint', () async {
    final asked = <String>[];
    final api = _api((r) {
      if (r.url.path.endsWith('/bookmark-lists/show')) {
        return _json(
          _page([
            _entry(5),
            {
              ..._entry(6),
              'itemType': 'post',
              'postId': 6,
              'entryId': null,
              'comments': 0,
            },
            {..._comment(7, 'entry_comment')},
            {..._comment(8, 'post_comment')},
          ]),
        );
      }
      asked.add(r.url.path);
      return _json({'isFavourited': false, 'userVote': -1});
    });

    await api.list();

    expect(
      asked,
      unorderedEquals([
        '/api/entry/5',
        '/api/post/6',
        '/api/comments/7',
        '/api/post-comments/8',
      ]),
    );
  });

  test('a reply that is not an object keeps the page working', () async {
    final api = _api(
      (r) => r.url.path.endsWith('/bookmark-lists/show')
          ? _json(_page([_entry(5), _entry(6)]))
          : http.Response('null', 200),
    );

    final (items, _) = await api.list();

    expect(items, hasLength(2));
  });
}
