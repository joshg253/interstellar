import 'package:flutter_test/flutter_test.dart';
import 'package:interstellar/src/screens/feed/cross_account_feed.dart';

DateTime t(int m) => DateTime.utc(2026, 1, 1, 0, m);

AccountFeedSource<int> source(String account, List<List<int>> pages) {
  return AccountFeedSource<int>(
    account: account,
    fetch: (page) async {
      final i = page.isEmpty ? 0 : int.parse(page);
      return (items: pages[i], next: i + 1 < pages.length ? '${i + 1}' : null);
    },
  );
}

Future<List<(String, int)>> drain(CrossAccountFeed<int> feed) async {
  final all = <(String, int)>[];
  while (feed.hasMore) {
    all.addAll(await feed.fetchNext());
  }
  return all;
}

void main() {
  fallbackTests();
  comparatorTests();
  // items are minutes; newest-first within each account
  test('merges newest-first across paginated accounts', () async {
    final feed = CrossAccountFeed<int>(
      sources: [
        source('a', [
          [50, 40],
          [10, 5],
        ]),
        source('b', [
          [45, 20],
          [15, 1],
        ]),
      ],
      createdAt: t,
      bufferTarget: 0,
    );
    final all = await drain(feed);
    expect(all.map((e) => e.$2), [50, 45, 40, 20, 15, 10, 5, 1]);
    expect(all.where((e) => e.$1 == 'a').length, 4);
  });

  test('a failing account does not break the other', () async {
    final feed = CrossAccountFeed<int>(
      sources: [
        source('a', [
          [3, 2, 1],
        ]),
        AccountFeedSource<int>(
          account: 'bad',
          fetch: (_) async => throw Exception('down'),
        ),
      ],
      createdAt: t,
    );
    final all = await drain(feed);
    expect(all.map((e) => e.$2), [3, 2, 1]);
    expect(feed.failed.map((s) => s.account), ['bad']);
  });

  test(
    'out-of-order head (pinned post) is neither duplicated nor lost',
    () async {
      final feed = CrossAccountFeed<int>(
        sources: [
          // 1 is an old pinned post sitting at the head
          source('a', [
            [1, 50, 40],
            [10],
          ]),
          source('b', [
            [45, 30],
            [20],
          ]),
        ],
        createdAt: t,
        bufferTarget: 0,
      );
      final all = await drain(feed);
      expect(all.map((e) => e.$2).toList()..sort(), [
        1,
        10,
        20,
        30,
        40,
        45,
        50,
      ]);
    },
  );

  test(
    'same key across accounts is emitted once and remembers accounts',
    () async {
      // value ~/ 10 is the identity: 51 and 52 are the same logical post
      final feed = CrossAccountFeed<int>(
        sources: [
          source('a', [
            [52, 40],
            [30],
          ]),
          source('b', [
            [51, 20],
            [11],
          ]),
        ],
        createdAt: t,
        keyOf: (i) => '${i ~/ 10}',
        bufferTarget: 0,
      );
      final all = await drain(feed);
      expect(all.map((e) => e.$2), [52, 40, 30, 20, 11]);
      expect(feed.accountsFor(52), ['a', 'b']);
      expect(feed.accountsFor(40), ['a']);
      expect(feed.copiesFor(52), [('a', 52), ('b', 51)]);
    },
  );

  test('does not emit past the unfetched bound', () async {
    final feed = CrossAccountFeed<int>(
      sources: [
        source('a', [
          [50, 10],
          [5],
        ]),
        source('b', [
          [40, 30],
          [20],
        ]),
      ],
      createdAt: t,
      bufferTarget: 0,
    );
    final first = await feed.fetchNext();
    // a's tail is 10, b's is 30: nothing older than 30 may be emitted yet
    expect(first.map((e) => e.$2), [50, 40, 30]);
  });
}

void comparatorTests() {
  test('honors a custom ordering and its unfetched bound', () async {
    // ascending: each source is sorted smallest first
    final feed = CrossAccountFeed<int>(
      sources: [
        source('a', [
          [1, 5],
          [9],
        ]),
        source('b', [
          [2, 3],
          [4],
        ]),
      ],
      compare: (a, b) => a.compareTo(b),
      bufferTarget: 0,
    );
    // tails are 5 and 3; nothing beyond 3 may be emitted yet
    expect((await feed.fetchNext()).map((e) => e.$2), [1, 2, 3]);
    expect((await drain(feed)).map((e) => e.$2), [4, 5, 9]);
  });
}

void fallbackTests() {
  test('copiesOf falls back to the item itself when it has no key', () async {
    final feed = CrossAccountFeed<int>(
      sources: [
        source('a', [
          [3, 2],
        ]),
      ],
      createdAt: t,
      keyOf: (i) => i == 3 ? null : '$i',
    );
    await drain(feed);
    expect(feed.copiesOf('a', 3), [('a', 3)]); // null key
    expect(feed.copiesOf('a', 2), [('a', 2)]); // keyed
    expect(feed.copiesOf('z', 9), [('z', 9)]); // never seen
  });
}
