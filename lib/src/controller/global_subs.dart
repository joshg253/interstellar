import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:interstellar/src/api/host_check.dart';
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

/// Seconds a server asked us to wait, from an error message that says
/// `retry after Ns`.
@visibleForTesting
Duration? retryAfterOf(String error) {
  final m = RegExp(r'retry after (\d+)s').firstMatch(error);
  return m == null ? null : Duration(seconds: int.parse(m.group(1)!));
}

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

  /// Servers that are gone: their entries are left out of the global list and
  /// never added to or removed from an account.
  final Set<String> dead = {};

  bool isDead(String name) => dead.contains(name.split('@').last);

  /// Sets the dead servers and drops their entries from the global lists.
  Future<void> setDead(Iterable<String> hosts) async {
    dead
      ..clear()
      ..addAll(
        hosts.map((h) => h.trim().toLowerCase()).where((h) => h.isNotEmpty),
      );
    for (final kind in master.keys) {
      master[kind]!.removeWhere(isDead);
    }
    problems.removeWhere((h, _) => dead.contains(h));
    notifyListeners();
    await _save();
  }

  /// How many entries the accounts hold on [hosts] (what a purge would try to
  /// remove).
  int heldOnAccounts(Set<String> hosts) => [
    for (final byAccount in snapshots.values)
      for (final snap in byAccount.values)
        for (final n in snap.subs)
          if (hosts.contains(n.split('@').last)) n,
  ].length;

  /// Marks [hosts] dead, and with [removeFromAccounts] also tries to remove
  /// their entries from every account that holds them, as one job. A gone
  /// server usually refuses that, and the refusals show as failures.
  Future<void> purge(
    Iterable<String> hosts, {
    bool removeFromAccounts = false,
  }) async {
    final set = hosts.map((h) => h.trim().toLowerCase()).toSet();
    await setDead([...dead, ...set]);
    if (!removeFromAccounts) return;
    await _runPlans({
      for (final kind in SubsKind.values)
        kind: {
          for (final e in snapshots[kind]!.entries)
            e.key: (
              add: <String>{},
              remove: {
                for (final n in e.value.subs)
                  if (set.contains(n.split('@').last)) n,
              },
            ),
        }..removeWhere((_, v) => v.remove.isEmpty),
    });
  }

  /// Servers that failed their last check and are still in the global list.
  final Map<String, HostProblem> problems = {};

  /// How many entries of the global list are on [host].
  int entriesOn(String host) => [
    for (final names in master.values)
      for (final n in names)
        if (n.contains('@') && n.split('@').last == host) n,
  ].length;

  /// Asks each server of the global list, not marked dead, whether it
  /// answers, and keeps how long each has been failing in [problems]. Several
  /// are asked at once; [onProgress] gets the number asked so far and the
  /// total, and [cancelled] stops the check early.
  Future<void> checkHosts(
    Future<({HostFailure kind, String detail})?> Function(String host) probe, {
    void Function(int done, int total)? onProgress,
    bool Function()? cancelled,
  }) async {
    final hosts = {
      for (final names in master.values)
        for (final n in names)
          if (n.contains('@')) n.split('@').last,
    }.where((h) => !dead.contains(h)).toList();
    var next = 0;
    var asked = 0;
    await Future.wait([
      for (var i = 0; i < 8; i++)
        () async {
          while (next < hosts.length && !(cancelled?.call() ?? false)) {
            final host = hosts[next++];
            ({HostFailure kind, String detail})? fault;
            try {
              fault = await probe(host);
            } catch (e) {
              fault = (kind: HostFailure.network, detail: '$e');
            }
            final now = DateTime.now();
            final old = problems[host];
            if (fault == null) {
              problems.remove(host);
            } else {
              problems[host] = HostProblem(
                kind: fault.kind,
                detail: fault.detail,
                since: old?.since ?? now,
                last: now,
                checks: (old?.checks ?? 0) + 1,
              );
            }
            onProgress?.call(++asked, hosts.length);
          }
        }(),
    ]);
    // Forget servers that are no longer in the list.
    problems.removeWhere((h, _) => !hosts.contains(h));
    notifyListeners();
    await _save();
  }

  /// Accounts with a snapshot of [kind].
  Iterable<String> fetched(SubsKind kind) => snapshots[kind]!.keys;

  bool get hasData => snapshots.values.any((m) => m.isNotEmpty);

  final Set<String> _busy = {};

  /// Accounts a job is working on now. Jobs on different accounts run at the
  /// same time; one on a busy account is refused.
  Set<String> get busy => _busy;
  bool get running => _busy.isNotEmpty;

  /// Accounts whose server asked us to slow down, until when. All work for
  /// such an account waits, not just the item that was refused.
  final Map<String, DateTime> pausedUntil = {};

  /// A short wait before each item of an account that was limited, doubled by
  /// every refusal and halved by every success.
  final Map<String, Duration> _gap = {};

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
        dead.addAll((data['dead'] as List?)?.cast<String>() ?? const []);
        for (final e in (data['hostProblems'] as Map? ?? {}).entries) {
          problems[e.key as String] = HostProblem.fromJson(
            (e.value as Map).cast<String, dynamic>(),
          );
        }
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
      dead.clear();
      problems.clear();
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() => store.write({
    'version': 2,
    'dead': dead.toList(),
    'hostProblems': {for (final e in problems.entries) e.key: e.value.toJson()},
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
    ...matrix(kind, snapshots[kind]!.keys).communities.where((n) => !isDead(n)),
  };

  /// What [account] lacks of the global list of [kind], or, with no global
  /// list yet, of what the other accounts hold.
  Set<String> missingFor(SubsKind kind, String account) {
    final have = snapshots[kind]![account]?.subs ?? <String>{};
    return {...(master[kind] ?? merged(kind))}
      ..removeAll(have)
      ..removeWhere(isDead);
  }

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
      accountTotal.remove(a);
      accountDone.remove(a);
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
          // The lists of one account are independent: fetch them together.
          await Future.wait([
            for (final kind in kinds)
              () async {
                if (_cancel) return;
                try {
                  final subs = await _retrying(
                    account,
                    () => fetch(account, kind, () => _cancel),
                  );
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
              }(),
          ]);
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

  /// When any account's lists were last fetched or changed.
  DateTime? get lastFetched {
    DateTime? latest;
    for (final byAccount in snapshots.values) {
      for (final snap in byAccount.values) {
        if (latest == null || snap.updated.isAfter(latest)) {
          latest = snap.updated;
        }
      }
    }
    return latest;
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

  /// Replaces the global list of [kind] with the merge of what the accounts
  /// hold now.
  Future<void> rebuildMaster(SubsKind kind) async {
    if (snapshots[kind]!.isEmpty) return;
    master[kind] = merged(kind);
    masterUpdated[kind] = DateTime.now();
    notifyListeners();
    await _save();
  }

  /// Rebuilds the global list of every kind that has been fetched.
  Future<void> rebuildAllMasters() async {
    final now = DateTime.now();
    for (final kind in SubsKind.values) {
      if (snapshots[kind]!.isEmpty) continue;
      master[kind] = merged(kind);
      masterUpdated[kind] = now;
    }
    notifyListeners();
    await _save();
  }

  /// Edits the global list of [kind]: adds and removes entries.
  Future<void> editMaster(
    SubsKind kind, {
    Iterable<String> add = const [],
    Iterable<String> remove = const [],
  }) async {
    master[kind] = {...?master[kind], ...add}..removeAll(remove);
    masterUpdated[kind] = DateTime.now();
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
    final todo = [
      for (final a in accounts)
        if (only == null || a == only)
          for (final c in missingFor(kind, a)) (a, c),
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
    await _refresh(kind, targets);
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
    await _refresh(kind, work.keys);
    for (final a in work.keys) {
      steps[a] = _cancel ? JobStep.cancelled : JobStep.done;
    }
    await _save();
    await _end(work.keys);
  }

  /// Reads [kind] back from each of [accounts] after changing it, so the cache
  /// shows what the server really holds (a change can be refused quietly or
  /// have side effects). A failed read keeps what the cache has.
  Future<void> _refresh(SubsKind kind, Iterable<String> accounts) async {
    if (_cancel) return;
    await Future.wait([
      for (final account in accounts)
        () async {
          try {
            final subs = await fetch(account, kind, () => _cancel);
            if (subs != null && !_cancel) {
              snapshots[kind]![account] = AccountSnapshot(subs, DateTime.now());
            }
          } catch (_) {
            // Keep the cache as it is.
          }
        }(),
    ]);
  }

  /// What it takes to make each of [targets] hold exactly [from] in the list
  /// [kind]. Accounts without a fetched list, or already matching, are left
  /// out.
  Map<String, ({Set<String> add, Set<String> remove})> planFor(
    SubsKind kind,
    Set<String> from,
    Iterable<String> targets,
  ) => {
    for (final t in targets)
      if (snapshots[kind]![t] != null)
        t: (
          add: from.difference(snapshots[kind]![t]!.subs)..removeWhere(isDead),
          remove: snapshots[kind]![t]!.subs.difference(from)
            ..removeWhere(isDead),
        ),
  }..removeWhere((_, v) => v.add.isEmpty && v.remove.isEmpty);

  /// The plan for making each of [targets] match the account [source].
  Map<String, ({Set<String> add, Set<String> remove})> replacePlan(
    SubsKind kind,
    String source,
    Iterable<String> targets,
  ) => planFor(kind, snapshots[kind]![source]?.subs ?? <String>{}, [
    for (final t in targets)
      if (t != source) t,
  ]);

  /// The plan for making each of [targets] match the saved global list.
  Map<String, ({Set<String> add, Set<String> remove})> masterPlan(
    SubsKind kind,
    Iterable<String> targets,
  ) => planFor(kind, master[kind] ?? <String>{}, targets);

  /// Makes each of [targets] match [source] exactly: adds what it lacks and
  /// removes what it has beyond it. The source is not changed.
  Future<void> replaceLists(
    SubsKind kind,
    String source,
    List<String> targets,
  ) => _runPlans({kind: replacePlan(kind, source, targets)});

  /// Makes each of [targets] match the saved global list exactly, for each of
  /// [kinds] that has one, as a single job.
  Future<void> applyMaster(Iterable<SubsKind> kinds, List<String> targets) =>
      _runPlans({
        for (final kind in kinds)
          if (master[kind] != null) kind: masterPlan(kind, targets),
      });

  Future<void> _runPlans(
    Map<SubsKind, Map<String, ({Set<String> add, Set<String> remove})>> plans,
  ) async {
    final accounts = {for (final p in plans.values) ...p.keys};
    if (accounts.isEmpty || !_begin(accounts)) return;
    for (final plan in plans.values) {
      for (final e in plan.entries) {
        final n = e.value.add.length + e.value.remove.length;
        accountTotal[e.key] = (accountTotal[e.key] ?? 0) + n;
        accountDone[e.key] = 0;
        total += n;
      }
    }
    await Future.wait([
      for (final account in accounts)
        () async {
          for (final entry in plans.entries) {
            final plan = entry.value[account];
            if (plan == null) continue;
            await _worker(account, entry.key, plan.add.toList());
            await _worker(
              account,
              entry.key,
              plan.remove.toList(),
              state: false,
            );
          }
        }(),
    ]);
    for (final entry in plans.entries) {
      await _refresh(entry.key, entry.value.keys);
    }
    for (final a in accounts) {
      steps[a] = _cancel ? JobStep.cancelled : JobStep.done;
    }
    await _save();
    await _end(accounts);
  }

  static const _perAccount = 3;

  Future<void> _worker(
    String account,
    SubsKind kind,
    List<String> names, {
    bool state = true,
  }) async {
    steps[account] = JobStep.running;
    // A caller doing several passes sets the totals up front.
    accountTotal.putIfAbsent(account, () => names.length);
    accountDone.putIfAbsent(account, () => 0);
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

  /// Runs [call] for [account], trying again when the server says it is being
  /// asked too often (HTTP 429) or the network dropped the request. A 429 holds
  /// back every request for that account for as long as the server asked (or a
  /// growing wait), and slows the account down afterwards. Other errors are not
  /// retried.
  Future<T> _retrying<T>(String account, Future<T> Function() call) async {
    for (var attempt = 0; ; attempt++) {
      await _waitTurn(account);
      try {
        final result = await call();
        final gap = _gap[account];
        if (gap != null) {
          final half = gap ~/ 2;
          half < retryDelay ~/ 50 ? _gap.remove(account) : _gap[account] = half;
        }
        return result;
      } catch (e) {
        final text = e.toString();
        final limited = text.contains('status 429');
        final dropped = text.contains('SocketException');
        if (!(limited || dropped) || attempt >= (limited ? 8 : 4) || _cancel) {
          rethrow;
        }
        var wait = retryAfterOf(text) ?? retryDelay * (1 << attempt);
        if (wait > const Duration(minutes: 5)) {
          wait = const Duration(minutes: 5);
        }
        if (limited) {
          final until = DateTime.now().add(wait);
          final old = pausedUntil[account];
          if (old == null || until.isAfter(old)) pausedUntil[account] = until;
          final gap = _gap[account] ?? retryDelay ~/ 10;
          final doubled = gap * 2;
          _gap[account] = doubled > retryDelay ? retryDelay : doubled;
          notifyListeners();
        } else {
          await Future<void>.delayed(wait);
        }
      }
    }
  }

  /// Waits out a pause the server asked for, then the account's short gap.
  Future<void> _waitTurn(String account) async {
    for (;;) {
      final until = pausedUntil[account];
      if (until == null) break;
      final left = until.difference(DateTime.now());
      if (left <= Duration.zero) {
        pausedUntil.remove(account);
        notifyListeners();
        break;
      }
      if (_cancel) return;
      await Future<void>.delayed(left);
    }
    final gap = _gap[account];
    if (gap != null && gap > Duration.zero) await Future<void>.delayed(gap);
  }

  Future<void> _applyWithRetry(
    String account,
    SubsKind kind,
    String name,
    bool state,
  ) => _retrying(account, () => apply(account, kind, name, state));

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
