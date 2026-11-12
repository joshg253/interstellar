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

/// [server] holds the lists per kind, then per account; applying changes them.
GlobalSubsController _make(
  _MemStore store, {
  Map<SubsKind, Map<String, Set<String>>> server = const {},
  Set<(String, SubsKind)> failing = const {},
  List<String>? applied,
}) {
  final live = {
    for (final k in SubsKind.values)
      k: {
        for (final e in (server[k] ?? <String, Set<String>>{}).entries)
          e.key: {...e.value},
      },
  };
  return GlobalSubsController(
    store: store,
    fetch: (account, kind, cancelled) async {
      if (failing.contains((account, kind))) throw StateError('down');
      return cancelled() ? null : {...?live[kind]![account]};
    },
    apply: (account, kind, name, state) async {
      applied?.add('$account ${kind.name} $name $state');
      final set = live[kind]!.putIfAbsent(account, () => {});
      state ? set.add(name) : set.remove(name);
    },
  );
}

void main() {
  tableTests();
  parallelTests();
  batchTests();
  progressTests();
  jobsTests();
  refreshTests();
  mirrorTests();
  masterTests();
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
      expect(bad.failures.single, startsWith('$a: communities'));
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

  test('a job cannot start on an account that is busy', () async {
    final c = _make(_MemStore());
    await c.load();
    final first = c.fetchAccounts([a]);
    await c.fetchAccounts([a, b]);
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
    final srv = <String, Set<String>>{
      a: {for (var i = 0; i < 12; i++) 'c$i@x.example'},
    };
    final c = GlobalSubsController(
      store: _MemStore(),
      fetch: (account, kind, cancelled) async => {...?srv[account]},
      apply: (account, kind, name, state) async {
        running++;
        if (running > peak) peak = running;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        (srv[account] ??= {}).add(name);
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
      final srv = <String, Set<String>>{
        a: {'ok@x.example', 'bad@x.example'},
      };
      final c = GlobalSubsController(
        store: _MemStore(),
        fetch: (account, kind, cancelled) async => {...?srv[account]},
        apply: (account, kind, name, state) async {
          if (name.startsWith('bad')) throw StateError('no');
          (srv[account] ??= {}).add(name);
        },
      );
      await c.load();
      await c.fetchAccounts([a, b]);
      await c.syncMissing(SubsKind.communities, [a, b]);
      expect(c.failures.single, startsWith('$b: bad@x.example'));
      expect(c.snapshots[SubsKind.communities]![b]!.subs, {'ok@x.example'});
    },
  );
}

void batchTests() {
  GlobalSubsController make(List<String> applied) {
    final srv = <String, Set<String>>{
      a: {'one@x.example', 'two@x.example'},
      b: {'two@x.example', 'three@x.example'},
    };
    return GlobalSubsController(
      store: _MemStore(),
      fetch: (account, kind, cancelled) async => {...?srv[account]},
      apply: (account, kind, name, state) async {
        applied.add('$account $name $state');
        state ? srv[account]!.add(name) : srv[account]!.remove(name);
      },
    );
  }

  test(
    'removing items from all accounts skips accounts without them',
    () async {
      final applied = <String>[];
      final c = make(applied);
      await c.load();
      await c.fetchAccounts([a, b]);
      await c.setMany(
        SubsKind.communities,
        ['one@x.example', 'two@x.example'],
        [a, b],
        false,
      );
      expect(applied.toSet(), {
        '$a one@x.example false',
        '$a two@x.example false',
        '$b two@x.example false',
      });
      expect(c.snapshots[SubsKind.communities]![a]!.subs, isEmpty);
      expect(c.snapshots[SubsKind.communities]![b]!.subs, {'three@x.example'});
    },
  );

  test('adding items to all accounts skips accounts that have them', () async {
    final applied = <String>[];
    final c = make(applied);
    await c.load();
    await c.fetchAccounts([a, b]);
    await c.setMany(
      SubsKind.communities,
      ['one@x.example', 'two@x.example'],
      [a, b],
      true,
    );
    expect(applied, ['$b one@x.example true']);
  });
}

void progressTests() {
  test('progress is counted per account', () async {
    final c = GlobalSubsController(
      store: _MemStore(),
      fetch: (account, kind, cancelled) async => account == a
          ? {'one@x.example', 'two@x.example', 'three@x.example'}
          : <String>{},
      apply: (account, kind, name, state) async {},
    );
    await c.load();
    await c.fetchAccounts([a, b]);
    // One step per list for each account.
    expect(c.accountTotal[a], SubsKind.values.length);
    expect(c.accountDone[a], SubsKind.values.length);
    await c.syncMissing(SubsKind.communities, [a, b]);
    expect(c.accountTotal[b], 3);
    expect(c.accountDone[b], 3);
    expect(c.accountTotal.containsKey(a), isFalse);
  });
}

void jobsTests() {
  GlobalSubsController make({
    required Future<void> Function(String, String, bool) apply,
    Duration retryDelay = Duration.zero,
  }) {
    final srv = <String, Set<String>>{
      'src@s.example': {'one@x.example', 'two@x.example'},
    };
    return GlobalSubsController(
      store: _MemStore(),
      retryDelay: retryDelay,
      fetch: (account, kind, cancelled) async => {...?srv[account]},
      apply: (account, kind, name, state) async {
        await apply(account, name, state);
        (srv[account] ??= {}).add(name);
      },
    );
  }

  const src = 'src@s.example';

  test('a failure is listed with its reason', () async {
    final c = make(apply: (acc, name, state) async => throw StateError('boom'));
    await c.load();
    await c.fetchAccounts([src, a]);
    await c.syncMissing(SubsKind.communities, [src, a], only: a);
    expect(c.failures, hasLength(2));
    expect(c.failures.first, allOf(contains(a), contains('one@x.example')));
    expect(c.failures.first, contains('boom'));
  });

  test('a rate limited item is retried and then goes through', () async {
    var calls = 0;
    final c = make(
      apply: (acc, name, state) async {
        calls++;
        if (calls <= 2) {
          throw Exception('Request failed with status 429: Too Many Requests');
        }
      },
    );
    await c.load();
    await c.fetchAccounts([src, a]);
    await c.syncMissing(SubsKind.communities, [src, a], only: a);
    expect(c.failures, isEmpty);
    expect(c.snapshots[SubsKind.communities]![a]!.subs, hasLength(2));
  });

  test('an item that stays rate limited gives up and is listed', () async {
    final c = make(
      apply: (acc, name, state) async =>
          throw Exception('Request failed with status 429'),
    );
    await c.load();
    await c.fetchAccounts([src, a]);
    await c.syncMissing(SubsKind.communities, [src, a], only: a);
    expect(c.failures, hasLength(2));
    expect(c.running, isFalse);
  });

  test('jobs on different accounts run at the same time', () async {
    final applied = <String>[];
    final c = make(
      apply: (acc, name, state) async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        applied.add('$acc $name');
      },
    );
    await c.load();
    await c.fetchAccounts([src, a, b]);
    final first = c.syncMissing(SubsKind.communities, [src, a, b], only: a);
    final second = c.syncMissing(SubsKind.communities, [src, a, b], only: b);
    expect(c.busy, containsAll([a, b]));
    await Future.wait([first, second]);
    expect(applied.where((e) => e.startsWith(a)), hasLength(2));
    expect(applied.where((e) => e.startsWith(b)), hasLength(2));
    expect(c.running, isFalse);
  });

  test('a second job on a busy account is refused', () async {
    final applied = <String>[];
    final c = make(
      apply: (acc, name, state) async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        applied.add('$acc $name');
      },
    );
    await c.load();
    await c.fetchAccounts([src, a]);
    final first = c.syncMissing(SubsKind.communities, [src, a], only: a);
    await c.syncMissing(SubsKind.communities, [src, a], only: a);
    await first;
    expect(applied, hasLength(2));
  });
}

void refreshTests() {
  test('after a sync the account list is read back from the server', () async {
    // The server quietly ignores names starting with "ghost".
    final server = <String, Set<String>>{
      'src@s.example': {'real@x.example', 'ghost@x.example'},
      a: {},
    };
    final c = GlobalSubsController(
      store: _MemStore(),
      fetch: (account, kind, cancelled) async => {...?server[account]},
      apply: (account, kind, name, state) async {
        if (!name.startsWith('ghost')) server[account]!.add(name);
      },
    );
    await c.load();
    await c.fetchAccounts(['src@s.example', a]);
    final before = c.snapshots[SubsKind.communities]![a]!.updated;
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await c.syncMissing(SubsKind.communities, ['src@s.example', a], only: a);
    final snap = c.snapshots[SubsKind.communities]![a]!;
    expect(snap.subs, {'real@x.example'});
    expect(snap.updated.isAfter(before), isTrue);
  });

  test('a cancelled sync does not read back', () async {
    var fetches = 0;
    late GlobalSubsController c;
    c = GlobalSubsController(
      store: _MemStore(),
      fetch: (account, kind, cancelled) async {
        fetches++;
        return account == 'src@s.example' ? {'one@x.example'} : <String>{};
      },
      apply: (account, kind, name, state) async => c.cancel(),
    );
    await c.load();
    await c.fetchAccounts(['src@s.example', a]);
    final after = fetches;
    await c.syncMissing(SubsKind.communities, ['src@s.example', a], only: a);
    expect(fetches, after);
  });
}

void mirrorTests() {
  const clean = 'clean@l.example';
  const messy = 'messy@l.example';
  const third = 'third@m.example';

  GlobalSubsController make(List<String> applied) {
    final srv = <String, Set<String>>{
      clean: {'keep@x.example', 'new@x.example'},
      messy: {'keep@x.example', 'junk1@x.example', 'junk2@x.example'},
      third: {'junk3@x.example'},
    };
    return GlobalSubsController(
      store: _MemStore(),
      fetch: (account, kind, cancelled) async => {...?srv[account]},
      apply: (account, kind, name, state) async {
        applied.add('$account $name $state');
        state ? srv[account]!.add(name) : srv[account]!.remove(name);
      },
    );
  }

  test('the plan lists what to add and what to remove', () async {
    final c = make([]);
    await c.load();
    await c.fetchAccounts([clean, messy, third]);
    final plan = c.replacePlan(SubsKind.communities, clean, [messy, third]);
    expect(plan[messy]!.add, {'new@x.example'});
    expect(plan[messy]!.remove, {'junk1@x.example', 'junk2@x.example'});
    expect(plan[third]!.add, {'keep@x.example', 'new@x.example'});
    expect(plan[third]!.remove, {'junk3@x.example'});
    expect(plan.containsKey(clean), isFalse);
  });

  test(
    'replacing makes the others match the source and leaves it alone',
    () async {
      final applied = <String>[];
      final c = make(applied);
      await c.load();
      await c.fetchAccounts([clean, messy, third]);
      await c.replaceLists(SubsKind.communities, clean, [messy, third]);
      final snaps = c.snapshots[SubsKind.communities]!;
      expect(snaps[messy]!.subs, {'keep@x.example', 'new@x.example'});
      expect(snaps[third]!.subs, {'keep@x.example', 'new@x.example'});
      expect(snaps[clean]!.subs, {'keep@x.example', 'new@x.example'});
      expect(applied.any((e) => e.startsWith(clean)), isFalse);
      expect(c.failures, isEmpty);
      expect(c.running, isFalse);
    },
  );

  test('an account that already matches is not touched', () async {
    final applied = <String>[];
    final c = make(applied);
    await c.load();
    await c.fetchAccounts([clean, messy, third]);
    await c.replaceLists(SubsKind.communities, clean, [messy]);
    applied.clear();
    await c.replaceLists(SubsKind.communities, clean, [messy]);
    expect(applied, isEmpty);
  });

  test('progress counts both the adds and the removes', () async {
    final c = make([]);
    await c.load();
    await c.fetchAccounts([clean, messy, third]);
    await c.replaceLists(SubsKind.communities, clean, [messy]);
    expect(c.accountTotal[messy], 3);
    expect(c.accountDone[messy], 3);
  });
}

void masterTests() {
  GlobalSubsController make(_MemStore store, List<String> applied) {
    final srv = <String, Set<String>>{
      a: {'one@x.example', 'junk@x.example'},
      b: {'two@y.example'},
    };
    return GlobalSubsController(
      store: store,
      fetch: (account, kind, cancelled) async => {...?srv[account]},
      apply: (account, kind, name, state) async {
        applied.add('$account $name $state');
        state ? srv[account]!.add(name) : srv[account]!.remove(name);
      },
    );
  }

  test(
    'the global list can be rebuilt, edited and survives a restart',
    () async {
      final store = _MemStore();
      final c = make(store, []);
      await c.load();
      await c.fetchAccounts([a, b]);
      await c.rebuildMaster(SubsKind.communities);
      expect(c.master[SubsKind.communities], {
        'one@x.example',
        'junk@x.example',
        'two@y.example',
      });
      await c.editMaster(
        SubsKind.communities,
        remove: ['junk@x.example'],
        add: ['new@z.example'],
      );
      expect(c.master[SubsKind.communities], {
        'one@x.example',
        'two@y.example',
        'new@z.example',
      });
      final again = make(store, []);
      await again.load();
      expect(again.master[SubsKind.communities], {
        'one@x.example',
        'two@y.example',
        'new@z.example',
      });
    },
  );

  test('applying the global list makes the chosen accounts match it', () async {
    final applied = <String>[];
    final c = make(_MemStore(), applied);
    await c.load();
    await c.fetchAccounts([a, b]);
    await c.rebuildMaster(SubsKind.communities);
    await c.editMaster(SubsKind.communities, remove: ['junk@x.example']);
    await c.applyMaster(SubsKind.communities, [a, b]);
    final snaps = c.snapshots[SubsKind.communities]!;
    expect(snaps[a]!.subs, {'one@x.example', 'two@y.example'});
    expect(snaps[b]!.subs, {'one@x.example', 'two@y.example'});
    expect(applied, contains('$a junk@x.example false'));
    expect(c.failures, isEmpty);
  });

  test('applying with no saved list does nothing', () async {
    final applied = <String>[];
    final c = make(_MemStore(), applied);
    await c.load();
    await c.fetchAccounts([a, b]);
    await c.applyMaster(SubsKind.communities, [a, b]);
    expect(applied, isEmpty);
  });

  test(
    'the plan against the global list says what changes per account',
    () async {
      final c = make(_MemStore(), []);
      await c.load();
      await c.fetchAccounts([a, b]);
      await c.rebuildMaster(SubsKind.communities);
      await c.editMaster(SubsKind.communities, remove: ['junk@x.example']);
      final plan = c.masterPlan(SubsKind.communities, [a, b]);
      expect(plan[a]!.add, {'two@y.example'});
      expect(plan[a]!.remove, {'junk@x.example'});
      expect(plan[b]!.add, {'one@x.example'});
      expect(plan[b]!.remove, isEmpty);
    },
  );
}
