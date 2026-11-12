import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:interstellar/src/controller/global_subs.dart';

class _MemStore implements SubsStore {
  Map<String, dynamic>? data;

  @override
  Future<Map<String, dynamic>?> read() async => data;

  @override
  Future<void> write(Map<String, dynamic> d) async => data = d;
}

const a = 'a@x.example';
const b = 'b@y.example';

/// [server] answers per kind, then per account.
GlobalSubsController _make(
  _MemStore store, {
  Map<SubsKind, Map<String, Set<String>>> server = const {},
  Set<(String, SubsKind)> failing = const {},
  List<String>? applied,
}) => GlobalSubsController(
  store: store,
  fetch: (account, kind, cancelled) async {
    if (failing.contains((account, kind))) throw StateError('down');
    return cancelled() ? null : server[kind]?[account] ?? {};
  },
  apply: (account, kind, name, state) async =>
      applied?.add('$account ${kind.name} $name $state'),
);

void main() {
  tableTests();
  parallelTests();
  test('fetching stores each account and survives a restart', () async {
    final store = _MemStore();
    final c = _make(
      store,
      server: {
        SubsKind.communities: {
          a: {'one@x.example', 'two@y.example'},
          b: {'two@y.example'},
        },
        SubsKind.userBlocks: {
          a: {'bob@z.example'},
        },
      },
    );
    await c.load();
    await c.fetchAccounts([a, b]);
    expect(c.running, isFalse);
    expect(c.snapshots[SubsKind.communities]![a]!.subs, hasLength(2));
    expect(c.merged(SubsKind.communities), {'one@x.example', 'two@y.example'});
    expect(c.merged(SubsKind.userBlocks), {'bob@z.example'});
    expect(c.merged(SubsKind.communityBlocks), isEmpty);

    final again = _make(store);
    await again.load();
    expect(again.snapshots[SubsKind.communities]![b]!.subs, {'two@y.example'});
    expect(again.snapshots[SubsKind.userBlocks]![a]!.subs, {'bob@z.example'});
  });

  test(
    'a failing list keeps its old snapshot and the rest still load',
    () async {
      final store = _MemStore();
      final first = _make(
        store,
        server: {
          SubsKind.communities: {
            a: {'one@x.example'},
          },
        },
      );
      await first.load();
      await first.fetchAccounts([a]);

      final bad = _make(
        store,
        server: {
          SubsKind.userBlocks: {
            a: {'bob@z.example'},
          },
        },
        failing: {(a, SubsKind.communities)},
      );
      await bad.load();
      await bad.fetchAccounts([a]);
      expect(bad.failures, ['$a: communities']);
      expect(bad.steps[a], JobStep.failed);
      expect(bad.snapshots[SubsKind.communities]![a]!.subs, {'one@x.example'});
      expect(bad.snapshots[SubsKind.userBlocks]![a]!.subs, {'bob@z.example'});
    },
  );

  test('cancel discards what a cancelled account fetched', () async {
    final c = _make(_MemStore());
    await c.load();
    final run = c.fetchAccounts([a]);
    c.cancel();
    await run;
    expect(c.steps[a], JobStep.cancelled);
    expect(c.hasData, isFalse);
    expect(c.running, isFalse);
  });

  test('saving the merged lists stores each deduplicated union', () async {
    final c = _make(
      _MemStore(),
      server: {
        SubsKind.communities: {
          a: {'one@x.example'},
          b: {'one@x.example', 'two@y.example'},
        },
      },
    );
    await c.load();
    await c.fetchAccounts([a, b]);
    expect(c.master, isEmpty);
    await c.saveMerged();
    expect(c.master[SubsKind.communities], {'one@x.example', 'two@y.example'});
    expect(c.masterUpdated[SubsKind.communities], isNotNull);
  });

  test('syncing fills only what each account lacks, in that list', () async {
    final applied = <String>[];
    final c = _make(
      _MemStore(),
      server: {
        SubsKind.userBlocks: {
          a: {'bob@z.example'},
          b: {'bob@z.example', 'eve@z.example'},
        },
        SubsKind.communities: {
          a: {'only-a@x.example'},
        },
      },
      applied: applied,
    );
    await c.load();
    await c.fetchAccounts([a, b]);
    await c.syncMissing(SubsKind.userBlocks, [a, b]);
    expect(applied, ['$a userBlocks eve@z.example true']);
    expect(
      c.snapshots[SubsKind.userBlocks]![a]!.subs,
      contains('eve@z.example'),
    );
    expect(c.snapshots[SubsKind.communities]![b]!.subs, isEmpty);
    expect(c.failures, isEmpty);
  });

  test('a job cannot start while another runs', () async {
    final c = _make(_MemStore());
    await c.load();
    final first = c.fetchAccounts([a]);
    await c.fetchAccounts([b]);
    expect(c.steps.containsKey(b), isFalse);
    await first;
  });

  test(
    'a file store reads back what it wrote and ignores a bad file',
    () async {
      final dir = Directory.systemTemp.createTempSync('subs_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/subs.json');
      final store = FileSubsStore(() async => file);
      expect(await store.read(), isNull);
      await store.write({'a': 1});
      expect(await store.read(), {'a': 1});
      file.writeAsStringSync('not json');
      expect(await store.read(), isNull);
    },
  );
}

void tableTests() {
  test('syncing onto one account leaves the others alone', () async {
    final applied = <String>[];
    final c = _make(
      _MemStore(),
      server: {
        SubsKind.communities: {
          a: {'only-a@x.example'},
          b: {'only-b@y.example'},
        },
      },
      applied: applied,
    );
    await c.load();
    await c.fetchAccounts([a, b]);
    await c.syncMissing(SubsKind.communities, [a, b], only: b);
    expect(applied, ['$b communities only-a@x.example true']);
    expect(c.snapshots[SubsKind.communities]![a]!.subs, {'only-a@x.example'});
  });
}

void parallelTests() {
  test('one account syncs several items at once, but never too many', () async {
    var running = 0;
    var peak = 0;
    final c = GlobalSubsController(
      store: _MemStore(),
      fetch: (account, kind, cancelled) async => account == a
          ? {for (var i = 0; i < 12; i++) 'c$i@x.example'}
          : <String>{},
      apply: (account, kind, name, state) async {
        running++;
        if (running > peak) peak = running;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        running--;
      },
    );
    await c.load();
    await c.fetchAccounts([a, b]);
    await c.syncMissing(SubsKind.communities, [a, b], only: b);
    expect(peak, greaterThan(1));
    expect(peak, lessThanOrEqualTo(4));
    expect(c.snapshots[SubsKind.communities]![b]!.subs, hasLength(12));
    expect(c.done, 12);
  });

  test(
    'a failure in a parallel sync is listed and the rest still go',
    () async {
      final c = GlobalSubsController(
        store: _MemStore(),
        fetch: (account, kind, cancelled) async =>
            account == a ? {'ok@x.example', 'bad@x.example'} : <String>{},
        apply: (account, kind, name, state) async {
          if (name.startsWith('bad')) throw StateError('no');
        },
      );
      await c.load();
      await c.fetchAccounts([a, b]);
      await c.syncMissing(SubsKind.communities, [a, b]);
      expect(c.failures, ['$b: bad@x.example']);
      expect(c.snapshots[SubsKind.communities]![b]!.subs, {'ok@x.example'});
    },
  );
}
