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
    Future<Set<String>?> Function(String account, bool Function() cancelled);

typedef SubsApplier =
    Future<void> Function(String account, String community, bool state);

/// Keeps every account's subscriptions cached on the device and runs the long
/// jobs (fetching, subscribing) in the background: the screen only watches.
class GlobalSubsController extends ChangeNotifier {
  GlobalSubsController({
    required this.store,
    required this.fetch,
    required this.apply,
  });

  final SubsStore store;
  final SubsFetcher fetch;
  final SubsApplier apply;

  final Map<String, AccountSnapshot> snapshots = {};

  /// The merged list the user saved, or null before the first save.
  Set<String>? master;
  DateTime? masterUpdated;

  String? _job;

  /// What is running ('fetch', 'subscribe'), or null when idle.
  String? get job => _job;
  bool get running => _job != null;

  /// Per account state of the current or last job.
  final Map<String, JobStep> steps = {};

  /// Items that could not be done in the current or last job.
  final List<String> failures = [];

  int total = 0;
  int done = 0;

  bool _cancel = false;
  bool _loaded = false;

  bool get loaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;
    final data = await store.read();
    try {
      if (data != null) {
        final accounts = data['accounts'] as Map<String, dynamic>? ?? {};
        for (final e in accounts.entries) {
          final v = e.value as Map<String, dynamic>;
          snapshots[e.key] = AccountSnapshot({
            ...(v['subs'] as List).cast<String>(),
          }, DateTime.parse(v['updated'] as String));
        }
        final m = data['master'] as List?;
        master = m == null ? null : {...m.cast<String>()};
        final mu = data['masterUpdated'] as String?;
        masterUpdated = mu == null ? null : DateTime.parse(mu);
      }
    } catch (_) {
      snapshots.clear();
      master = null;
      masterUpdated = null;
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() => store.write({
    'version': 1,
    'master': master?.toList(),
    'masterUpdated': masterUpdated?.toIso8601String(),
    'accounts': {
      for (final e in snapshots.entries)
        e.key: {
          'subs': e.value.subs.toList(),
          'updated': e.value.updated.toIso8601String(),
        },
    },
  });

  /// What the cache says each of [accounts] is subscribed to.
  SubscriptionMatrix matrix(Iterable<String> accounts) => SubscriptionMatrix({
    for (final a in accounts) a: snapshots[a]?.subs ?? <String>{},
  });

  /// The deduplicated union of every account's subscriptions.
  Set<String> get merged {
    final m = matrix(snapshots.keys);
    return {...m.communities};
  }

  void cancel() {
    if (running) _cancel = true;
  }

  bool _begin(String job, Iterable<String> accounts) {
    if (running) return false;
    _job = job;
    _cancel = false;
    failures.clear();
    steps
      ..clear()
      ..addEntries(accounts.map((a) => MapEntry(a, JobStep.waiting)));
    total = steps.length;
    done = 0;
    notifyListeners();
    return true;
  }

  Future<void> _end() async {
    _job = null;
    notifyListeners();
  }

  /// Fetches the subscriptions of [accounts] from their servers. An account
  /// that fails or is cancelled keeps its previous snapshot.
  Future<void> fetchAccounts(List<String> accounts) async {
    if (!_begin('fetch', accounts)) return;
    await Future.wait([
      for (final account in accounts)
        () async {
          steps[account] = JobStep.running;
          notifyListeners();
          try {
            final subs = await fetch(account, () => _cancel);
            if (subs == null || _cancel) {
              steps[account] = JobStep.cancelled;
            } else {
              snapshots[account] = AccountSnapshot(subs, DateTime.now());
              steps[account] = JobStep.done;
            }
          } catch (_) {
            steps[account] = JobStep.failed;
            failures.add(account);
          }
          done++;
          notifyListeners();
        }(),
    ]);
    await _save();
    await _end();
  }

  /// Saves the merged list of what the cache holds as the local master list.
  Future<void> saveMerged() async {
    master = merged;
    masterUpdated = DateTime.now();
    notifyListeners();
    await _save();
  }

  /// Subscribes each account to every community the others have and it lacks,
  /// judging by the cache. One at a time so a server's rate limit holds.
  Future<void> subscribeMissing(List<String> accounts) async {
    final m = matrix(accounts);
    final todo = [
      for (final a in m.accounts)
        for (final c in m.missing(a)) (a, c),
    ];
    if (todo.isEmpty || !_begin('subscribe', accounts)) return;
    total = todo.length;
    for (final (account, community) in todo) {
      if (_cancel) break;
      steps[account] = JobStep.running;
      notifyListeners();
      try {
        await apply(account, community, true);
        snapshots[account] = AccountSnapshot({
          ...?snapshots[account]?.subs,
          community,
        }, snapshots[account]?.updated ?? DateTime.now());
      } catch (_) {
        failures.add('$account: $community');
      }
      done++;
      notifyListeners();
    }
    for (final a in accounts) {
      steps[a] = _cancel ? JobStep.cancelled : JobStep.done;
    }
    await _save();
    await _end();
  }

  /// Subscribes or unsubscribes one account right away and updates the cache.
  Future<bool> setOne(String account, String community, bool state) async {
    try {
      await apply(account, community, state);
    } catch (_) {
      return false;
    }
    final old = snapshots[account];
    final subs = {...?old?.subs};
    state ? subs.add(community) : subs.remove(community);
    snapshots[account] = AccountSnapshot(subs, old?.updated ?? DateTime.now());
    notifyListeners();
    await _save();
    return true;
  }
}
