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

GlobalSubsController _make(
  _MemStore store, {
  Map<String, Set<String>> server = const {},
  Set<String> failing = const {},
  List<String>? applied,
}) => GlobalSubsController(
  store: store,
  fetch: (account, cancelled) async {
    if (failing.contains(account)) throw StateError('down');
    return cancelled() ? null : server[account] ?? {};
  },
  apply: (account, community, state) async =>
      applied?.add('$account $community $state'),
);

void main() {
  test('fetching stores each account and survives a restart', () async {
    final store = _MemStore();
    final c = _make(
      store,
      server: {
        'a@x.example': {'one@x.example', 'two@y.example'},
        'b@y.example': {'two@y.example'},
      },
    );
    await c.load();
    await c.fetchAccounts(['a@x.example', 'b@y.example']);
    expect(c.running, isFalse);
    expect(c.snapshots['a@x.example']!.subs, hasLength(2));
    expect(c.merged, {'one@x.example', 'two@y.example'});

    final again = _make(store);
    await again.load();
    expect(again.snapshots['b@y.example']!.subs, {'two@y.example'});
  });

  test('one failing account keeps its old snapshot and is reported', () async {
    final store = _MemStore();
    final c = _make(
      store,
      server: {
        'a@x.example': {'one@x.example'},
      },
    );
    await c.load();
    await c.fetchAccounts(['a@x.example']);
    final bad = _make(store, failing: {'a@x.example'});
    await bad.load();
    await bad.fetchAccounts(['a@x.example']);
    expect(bad.failures, ['a@x.example']);
    expect(bad.steps['a@x.example'], JobStep.failed);
    expect(bad.snapshots['a@x.example']!.subs, {'one@x.example'});
  });

  test('cancel discards what the cancelled account fetched', () async {
    final c = _make(_MemStore());
    await c.load();
    final run = c.fetchAccounts(['a@x.example']);
    c.cancel();
    await run;
    expect(c.steps['a@x.example'], JobStep.cancelled);
    expect(c.snapshots, isEmpty);
    expect(c.running, isFalse);
  });

  test('saving the merged list stores the deduplicated union', () async {
    final store = _MemStore();
    final c = _make(
      store,
      server: {
        'a@x.example': {'one@x.example'},
        'b@y.example': {'one@x.example', 'two@y.example'},
      },
    );
    await c.load();
    await c.fetchAccounts(['a@x.example', 'b@y.example']);
    expect(c.master, isNull);
    await c.saveMerged();
    expect(c.master, {'one@x.example', 'two@y.example'});
    expect(c.masterUpdated, isNotNull);
  });

  test('subscribing fills only what each account lacks', () async {
    final applied = <String>[];
    final c = _make(
      _MemStore(),
      server: {
        'a@x.example': {'one@x.example'},
        'b@y.example': {'one@x.example', 'two@y.example'},
      },
      applied: applied,
    );
    await c.load();
    await c.fetchAccounts(['a@x.example', 'b@y.example']);
    await c.subscribeMissing(['a@x.example', 'b@y.example']);
    expect(applied, ['a@x.example two@y.example true']);
    expect(c.snapshots['a@x.example']!.subs, contains('two@y.example'));
    expect(c.failures, isEmpty);
  });

  test('a job cannot start while another runs', () async {
    final c = _make(_MemStore());
    await c.load();
    final first = c.fetchAccounts(['a@x.example']);
    await c.fetchAccounts(['b@y.example']);
    expect(c.steps.containsKey('b@y.example'), isFalse);
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
