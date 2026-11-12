import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:interstellar/src/utils/subscription_matrix.dart';

/// One account's subscriptions as last fetched from its server.
class AccountSnapshot {
  const AccountSnapshot(this.subs, this.updated);

  final Set<String> subs;
  final DateTime updated;
}

enum JobStep { waiting, running, done, failed, cancelled }

/// The lists kept per account.
enum SubsKind { communities, communityBlocks, userBlocks }

/// Where the cache lives. Replaceable so tests need no disk.
abstract class SubsStore {
  Future<Map<String, dynamic>?> read();
  Future<void> write(Map<String, dynamic> data);
}

class FileSubsStore implements SubsStore {
  FileSubsStore(this.file);

  final Future<File> Function() file;

  @override
  Future<Map<String, dynamic>?> read() async {
    try {
      final f = await file();
      if (!f.existsSync()) return null;
      return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(Map<String, dynamic> data) async {
    final f = await file();
    await f.create(recursive: true);
    await f.writeAsString(jsonEncode(data));
  }
}

/// Fetches an account's subscriptions. Stops and returns null when
/// [cancelled] turns true.
typedef SubsFetcher =
    Future<Set<String>?> Function(
      String account,
      SubsKind kind,
      bool Function() cancelled,
    );

typedef SubsApplier =
    Future<void> Function(
      String account,
      SubsKind kind,
      String name,
      bool state,
    );

/// Keeps every account's subscriptions cached on the device and runs the long
/// jobs (fetching, subscribing) in the background: the screen only watches.
class GlobalSubsController extends ChangeNotifier {
  GlobalSubsController({
    required this.store,
    required this.fetch,
    required this.apply,
    this.retryDelay = const Duration(seconds: 5),
  });

  /// How long to wait before retrying an item a server rate limited; doubles
  /// with each try.
  final Duration retryDelay;

  final SubsStore store;
  final SubsFetcher fetch;
  final SubsApplier apply;

  final Map<SubsKind, Map<String, AccountSnapshot>> snapshots = {
    for (final k in SubsKind.values) k: {},
  };

  /// The merged lists the user saved, per kind.
  final Map<SubsKind, Set<String>> master = {};
  final Map<SubsKind, DateTime> masterUpdated = {};

  /// Accounts with a snapshot of [kind].
  Iterable<String> fetched(SubsKind kind) => snapshots[kind]!.keys;

  bool get hasData => snapshots.values.any((m) => m.isNotEmpty);

  final Set<String> _busy = {};

  /// Accounts a job is working on now. Jobs on different accounts run at the
  /// same time; one on a busy account is refused.
  Set<String> get busy => _busy;
  bool get running => _busy.isNotEmpty;

  /// Per account state of the current or last job.
  final Map<String, JobStep> steps = {};

  /// Items that could not be done in the current or last job.
  final List<String> failures = [];

  int total = 0;
  int done = 0;

  /// Steps of the current or last job, per account.
  final Map<String, int> accountTotal = {};
  final Map<String, int> accountDone = {};

  bool _cancel = false;
  bool _loaded = false;

  bool get loaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;
    final data = await store.read();
    try {
      if (data != null) {
        final kinds = data['kinds'] as Map<String, dynamic>? ?? {};
        for (final kind in SubsKind.values) {
          final k = kinds[kind.name] as Map<String, dynamic>?;
          if (k == null) continue;
          final accounts = k['accounts'] as Map<String, dynamic>? ?? {};
          for (final e in accounts.entries) {
            final v = e.value as Map<String, dynamic>;
            snapshots[kind]![e.key] = AccountSnapshot({
              ...(v['subs'] as List).cast<String>(),
            }, DateTime.parse(v['updated'] as String));
          }
          final m = k['master'] as List?;
          if (m != null) {
            master[kind] = {...m.cast<String>()};
            masterUpdated[kind] = DateTime.parse(k['masterUpdated'] as String);
          }
        }
      }
    } catch (_) {
      for (final m in snapshots.values) {
        m.clear();
      }
      master.clear();
      masterUpdated.clear();
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() => store.write({
    'version': 2,
    'kinds': {
      for (final kind in SubsKind.values)
        kind.name: {
          'master': master[kind]?.toList(),
          'masterUpdated': masterUpdated[kind]?.toIso8601String(),
          'accounts': {
            for (final e in snapshots[kind]!.entries)
              e.key: {
                'subs': e.value.subs.toList(),
                'updated': e.value.updated.toIso8601String(),
              },
          },
        },
    },
  });

  /// What the cache says each of [accounts] has in the list [kind].
  SubscriptionMatrix matrix(SubsKind kind, Iterable<String> accounts) =>
      SubscriptionMatrix({
        for (final a in accounts) a: snapshots[kind]![a]?.subs ?? <String>{},
      });

  /// The deduplicated union of every account's list [kind].
  Set<String> merged(SubsKind kind) => {
    ...matrix(kind, snapshots[kind]!.keys).communities,
  };

  void cancel() {
    if (running) _cancel = true;
  }

  bool _begin(Iterable<String> accounts) {
    if (accounts.any(_busy.contains)) return false;
    if (!running) {
      _cancel = false;
      failures.clear();
      steps.clear();
      total = 0;
      done = 0;
      accountTotal.clear();
      accountDone.clear();
    }
    _busy.addAll(accounts);
    for (final a in accounts) {
      steps[a] = JobStep.waiting;
    }
    notifyListeners();
    return true;
  }

  Future<void> _end(Iterable<String> accounts) async {
    _busy.removeAll(accounts);
    notifyListeners();
  }

  /// The first line of an error, short enough to list.
  static String why(Object e) {
    final text = e.toString().replaceFirst('Exception: ', '').split('\n').first;
    return text.length > 140 ? '${text.substring(0, 140)}…' : text;
  }

  /// Fetches the lists [kinds] of [accounts] from their servers. A list that
  /// fails or is cancelled keeps its previous snapshot.
  Future<void> fetchAccounts(
    List<String> accounts, {
    List<SubsKind> kinds = SubsKind.values,
  }) async {
    if (!_begin(accounts)) return;
    total += accounts.length;
    await Future.wait([
      for (final account in accounts)
        () async {
          steps[account] = JobStep.running;
          accountTotal[account] = kinds.length;
          accountDone[account] = 0;
          notifyListeners();
          var failed = false;
          for (final kind in kinds) {
            if (_cancel) break;
            try {
              final subs = await fetch(account, kind, () => _cancel);
              if (subs != null && !_cancel) {
                snapshots[kind]![account] = AccountSnapshot(
                  subs,
                  DateTime.now(),
                );
              }
            } catch (e) {
              failed = true;
              failures.add('$account: ${kind.name} — ${why(e)}');
            }
            accountDone[account] = accountDone[account]! + 1;
            notifyListeners();
          }
          steps[account] = _cancel
              ? JobStep.cancelled
              : failed
              ? JobStep.failed
              : JobStep.done;
          done++;
          notifyListeners();
        }(),
    ]);
    await _save();
    await _end(accounts);
  }

  /// Saves the merged list of each kind the cache holds as the local master.
  Future<void> saveMerged() async {
    final now = DateTime.now();
    for (final kind in SubsKind.values) {
      if (snapshots[kind]!.isEmpty) continue;
      master[kind] = merged(kind);
      masterUpdated[kind] = now;
    }
    notifyListeners();
    await _save();
  }

  /// Subscribes (or blocks) each account to everything the others have in the
  /// list [kind] and it lacks, judging by the cache; with [only], just that
  /// account, a few at a time.
  Future<void> syncMissing(
    SubsKind kind,
    List<String> accounts, {
    String? only,
  }) async {
    final m = matrix(kind, accounts);
    final todo = [
      for (final a in m.accounts)
        if (only == null || a == only)
          for (final c in m.missing(a)) (a, c),
    ];
    final targets = {for (final t in todo) t.$1};
    if (todo.isEmpty || !_begin(targets)) return;
    total += todo.length;
    // A few at a time per account (a server's rate limit is per account);
    // different accounts run side by side.
    await Future.wait([
      for (final account in {for (final t in todo) t.$1})
        _worker(account, kind, [
          for (final t in todo)
            if (t.$1 == account) t.$2,
        ]),
    ]);
    for (final a in targets) {
      steps[a] = _cancel ? JobStep.cancelled : JobStep.done;
    }
    await _save();
    await _end(targets);
  }

  /// Makes [names] present (or absent, with [state] false) on every one of
  /// [accounts] that is not already so, in the background.
  Future<void> setMany(
    SubsKind kind,
    List<String> names,
    List<String> accounts,
    bool state,
  ) async {
    final work = {
      for (final account in accounts)
        account: [
          for (final n in names)
            if ((snapshots[kind]![account]?.subs.contains(n) ?? false) != state)
              n,
        ],
    }..removeWhere((_, v) => v.isEmpty);
    if (work.isEmpty || !_begin(work.keys)) return;
    total += work.values.fold(0, (sum, v) => sum + v.length);
    await Future.wait([
      for (final e in work.entries) _worker(e.key, kind, e.value, state: state),
    ]);
    for (final a in work.keys) {
      steps[a] = _cancel ? JobStep.cancelled : JobStep.done;
    }
    await _save();
    await _end(work.keys);
  }

  static const _perAccount = 3;

  Future<void> _worker(
    String account,
    SubsKind kind,
    List<String> names, {
    bool state = true,
  }) async {
    steps[account] = JobStep.running;
    accountTotal[account] = names.length;
    accountDone[account] = 0;
    notifyListeners();
    var next = 0;
    await Future.wait([
      for (var i = 0; i < _perAccount; i++)
        () async {
          while (!_cancel && next < names.length) {
            final name = names[next++];
            try {
              await _applyWithRetry(account, kind, name, state);
              _remember(account, kind, name, state);
            } catch (e) {
              failures.add('$account: $name — ${why(e)}');
            }
            accountDone[account] = accountDone[account]! + 1;
            done++;
            notifyListeners();
          }
        }(),
    ]);
  }

  /// Tries again, after a growing wait, when the server says it is being asked
  /// too often (HTTP 429).
  Future<void> _applyWithRetry(
    String account,
    SubsKind kind,
    String name,
    bool state,
  ) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await apply(account, kind, name, state);
      } catch (e) {
        final limited = e.toString().contains('status 429');
        if (!limited || attempt >= 4 || _cancel) rethrow;
        await Future<void>.delayed(retryDelay * (1 << attempt));
      }
    }
  }

  void _remember(String account, SubsKind kind, String name, bool state) {
    final old = snapshots[kind]![account];
    final subs = {...?old?.subs};
    state ? subs.add(name) : subs.remove(name);
    snapshots[kind]![account] = AccountSnapshot(
      subs,
      old?.updated ?? DateTime.now(),
    );
  }

  /// Changes one account's list right away and updates the cache.
  Future<bool> setOne(
    String account,
    SubsKind kind,
    String name,
    bool state,
  ) async {
    try {
      await apply(account, kind, name, state);
    } catch (_) {
      return false;
    }
    _remember(account, kind, name, state);
    notifyListeners();
    await _save();
    return true;
  }
}
