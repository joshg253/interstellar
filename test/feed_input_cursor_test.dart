import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:interstellar/src/api/feed_source.dart';
import 'package:interstellar/src/controller/controller.dart';
import 'package:interstellar/src/controller/server.dart';
import 'package:interstellar/src/models/post.dart';
import 'package:interstellar/src/screens/feed/feed_agregator.dart';

class _NoController implements AppController {
  @override
  ServerSoftware get serverSoftware => ServerSoftware.lemmy;

  @override
  bool get isLoggedIn => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  test('a fetch leaves the cursor alone until it is committed', () async {
    final requested = <String?>[];
    final input = FeedInputState(
      title: 'a',
      source: FeedSource.all,
      sourceId: null,
      loadPage: (page, view, sort) async {
        requested.add(page);
        return const PostListModel(items: [], nextPage: '2');
      },
    );

    // e.g. another source failed, so the aggregator never committed this one
    await input.fetchPage(_NoController(), '', FeedView.threads, FeedSort.hot);
    await input.fetchPage(_NoController(), '', FeedView.threads, FeedSort.hot);

    expect(requested, [null, null]);
  });

  test('a committed cursor is used for the next fetch', () async {
    final requested = <String?>[];
    final input = FeedInputState(
      title: 'a',
      source: FeedSource.all,
      sourceId: null,
      loadPage: (page, view, sort) async {
        requested.add(page);
        return const PostListModel(items: [], nextPage: '2');
      },
    );

    final (_, next) = await input.fetchPage(
      _NoController(),
      '',
      FeedView.threads,
      FeedSort.hot,
    );
    input.cursor = next;
    await input.fetchPage(_NoController(), '', FeedView.threads, FeedSort.hot);

    expect(requested, [null, '2']);
  });

  test('a failed source does not advance the other sources', () async {
    final requestedA = <String?>[];
    final requestedB = <String?>[];
    var bFails = true;
    FeedInputState input(List<String?> requested, bool Function() fails) =>
        FeedInputState(
          title: 'x',
          source: FeedSource.all,
          sourceId: null,
          loadPage: (page, view, sort) async {
            requested.add(page);
            if (fails()) throw Exception('network');
            return const PostListModel(items: [], nextPage: '2');
          },
        );
    final aggregator = FeedAggregator(
      name: 'x',
      inputs: [input(requestedA, () => false), input(requestedB, () => bFails)],
    );
    final ac = _NoController();

    await expectLater(
      aggregator.fetchPage(ac, '', FeedView.threads, FeedSort.hot),
      throwsException,
    );
    bFails = false;
    await aggregator.fetchPage(ac, '', FeedView.threads, FeedSort.hot);

    expect(requestedA, [null, null]);
    expect(requestedB, [null, null]);
  });

  test(
    'a fetch that finishes after a refresh does not move the cursor',
    () async {
      final requested = <String?>[];
      final slow = Completer<PostListModel>();
      var first = true;
      final aggregator = FeedAggregator(
        name: 'x',
        inputs: [
          FeedInputState(
            title: 'x',
            source: FeedSource.all,
            sourceId: null,
            loadPage: (page, view, sort) {
              requested.add(page);
              if (first) {
                first = false;
                return slow.future;
              }
              return Future.value(
                const PostListModel(items: [], nextPage: '2'),
              );
            },
          ),
        ],
      );
      final ac = _NoController();

      final stale = aggregator.fetchPage(
        ac,
        '',
        FeedView.threads,
        FeedSort.hot,
      );
      aggregator.refresh();
      slow.complete(const PostListModel(items: [], nextPage: '9'));
      await stale;
      await aggregator.fetchPage(ac, '', FeedView.threads, FeedSort.hot);

      expect(requested, [null, null]);
    },
  );
}
