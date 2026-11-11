import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:interstellar/src/api/client.dart';
import 'package:interstellar/src/api/feed_source.dart';
import 'package:interstellar/src/api/microblogs.dart';
import 'package:interstellar/src/api/threads.dart';
import 'package:interstellar/src/controller/server.dart';
import 'package:interstellar/src/models/post.dart';

Map<String, dynamic> _item(int id, String type) => {
  'itemType': type,
  if (type == 'entry') 'entryId': id else 'postId': id,
  'user': {
    'userId': 1,
    'username': 'alice',
    'createdAt': '2026-01-01T00:00:00+00:00',
    'isBot': false,
  },
  'magazine': {'magazineId': 2, 'name': 'news'},
  'domain': null,
  'title': 'Item $id',
  'type': 'article',
  'image': null,
  'body': null,
  'lang': 'en',
  'numComments': 0,
  'comments': 0,
  'favourites': 3,
  'dv': 0,
  'uv': 0,
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

ServerClient _client(
  List<String> paths, [
  List<Map<String, String>>? queries,
]) => ServerClient(
  httpClient: MockClient((r) async {
    paths.add(r.url.path);
    queries?.add(r.url.queryParameters);
    return http.Response(
      jsonEncode({
        'items': [_item(1, 'entry'), _item(2, 'post')],
        'pagination': {'currentPage': 1, 'maxPage': 1},
      }),
      200,
      headers: {'content-type': 'application/json'},
    );
  }),
  software: ServerSoftware.mbin,
  domain: 'mbin.example.com',
);

void main() {
  test('the bookmarks source lists bookmarks, not upvoted items', () async {
    final paths = <String>[];
    final list = await APIThreads(
      _client(paths),
    ).list(FeedSource.favorited, combined: true);

    expect(paths, ['/api/bookmark-lists/show']);
    expect(list.items.map((p) => p.type), [
      PostType.thread,
      PostType.microblog,
    ]);
  });

  test('each feed view keeps only its own kind of bookmark', () async {
    final threads = await APIThreads(_client([])).list(FeedSource.favorited);
    final posts = await MbinAPIMicroblogs(
      _client([]),
    ).list(FeedSource.favorited);

    expect(threads.items.map((p) => p.type), [PostType.thread]);
    expect(posts.items.map((p) => p.type), [PostType.microblog]);
  });

  test(
    'the feed sort picks the order of the bookmarks, as the server knows it',
    () async {
      final queries = <Map<String, String>>[];
      await APIThreads(
        _client([], queries),
      ).list(FeedSource.favorited, sort: FeedSort.oldest);
      await MbinAPIMicroblogs(
        _client([], queries),
      ).list(FeedSource.favorited, sort: FeedSort.top);
      // Mbin lists bookmarks only by newest, oldest, top and hot.
      await APIThreads(
        _client([], queries),
      ).list(FeedSource.favorited, sort: FeedSort.commented);

      expect(queries.map((q) => q['sort']), ['oldest', 'top', 'newest']);
    },
  );
}
