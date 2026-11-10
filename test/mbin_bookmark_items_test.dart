import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:interstellar/src/api/bookmark.dart';
import 'package:interstellar/src/api/client.dart';
import 'package:interstellar/src/controller/server.dart';
import 'package:interstellar/src/models/post.dart';

Map<String, dynamic> _entry(int id) => {
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
  'isFavourited': false,
  'userVote': 0,
  'isOc': false,
  'isAdult': false,
  'isPinned': false,
  'isLocked': false,
  'createdAt': '2026-01-01T00:00:00+00:00',
  'lastActive': '2026-01-01T00:00:00+00:00',
  'visibility': 'visible',
  'bookmarks': <String>[],
};

void main() {
  test('a page whose items Mbin sent as an object is still read', () async {
    final api = APIBookmark(
      ServerClient(
        httpClient: MockClient(
          (r) async => http.Response(
            jsonEncode({
              // PHP writes an array with gaps in its keys as an object
              'items': {'0': _entry(1), '2': _entry(3)},
              'pagination': {'currentPage': 1, 'maxPage': 1},
            }),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
        software: ServerSoftware.mbin,
        domain: 'mbin.example.com',
      ),
    );

    final (items, _) = await api.list();

    expect(items.map((i) => (i as PostModel).id), [1, 3]);
  });
}
