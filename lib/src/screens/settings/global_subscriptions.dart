import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:interstellar/src/api/blocks.dart';
import 'package:interstellar/src/api/mastodon.dart';
import 'package:interstellar/src/controller/controller.dart';
import 'package:interstellar/src/controller/global_subs.dart';
import 'package:interstellar/src/controller/router.gr.dart';
import 'package:interstellar/src/controller/server.dart';
import 'package:interstellar/src/screens/explore/explore_screen.dart';
import 'package:interstellar/src/utils/utils.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

const _maxPages = 100;

GlobalSubsController? _instance;

/// The one controller for the app, so a job outlives the screen that began it.
GlobalSubsController globalSubsFor(AppController ac) =>
    _instance ??= GlobalSubsController(
      store: FileSubsStore(() async {
        final dir = await getApplicationSupportDirectory();
        return File(p.join(dir.path, 'global_subscriptions.json'));
      }),
      fetch: (account, kind, cancelled) async {
        final api = await ac.getApiForAccount(account);
        final host = account.split('@').last;
        if (api.client.software == ServerSoftware.mastodon) {
          final masto = MastodonAPI(api.client);
          return switch (kind) {
            SubsKind.communities => mastodonAccountNames(
              await masto.following(),
              host,
              groups: true,
            ),
            SubsKind.communityBlocks => mastodonAccountNames(
              await masto.blocked(),
              host,
              groups: true,
            ),
            SubsKind.userBlocks => mastodonAccountNames(
              await masto.blocked(),
              host,
              groups: false,
            ),
          };
        }
        switch (kind) {
          case SubsKind.communityBlocks:
            return listBlocked(api, host, users: false, cancelled: cancelled);
          case SubsKind.userBlocks:
            return listBlocked(api, host, users: true, cancelled: cancelled);
          case SubsKind.communities:
            final names = <String>{};
            String? page;
            var pages = 0;
            do {
              if (cancelled()) return null;
              final res = await api.community.list(
                page: page,
                filter: ExploreFilter.subscribed,
              );
              names.addAll(res.items.map((e) => normalizeName(e.name, host)));
              page = res.nextPage;
            } while (page != null && ++pages < _maxPages);
            return names;
        }
      },
      apply: (account, kind, name, state) async {
        final api = await ac.getApiForAccount(account);
        final host = account.split('@').last;
        if (api.client.software == ServerSoftware.mastodon) {
          final masto = MastodonAPI(api.client);
          final id = await masto.resolveAccount(name);
          if (kind == SubsKind.communities) {
            await masto.setFollow(id, state);
          } else {
            await masto.setBlock(id, state);
          }
          return;
        }
        final local = denormalizeName(name, host);
        switch (kind) {
          case SubsKind.communities:
            final found = await api.community.getByName(local);
            if (found.isUserSubscribed != state) {
              await api.community.subscribe(found.id, state);
            }
          case SubsKind.communityBlocks:
            final found = await api.community.getByName(local);
            if ((found.isBlockedByUser ?? false) != state) {
              await api.community.block(found.id, state);
            }
          case SubsKind.userBlocks:
            final found = await api.users.getByName(local);
            if ((found.isBlockedByUser ?? false) != state) {
              await api.users.putBlock(found.id, state);
            }
        }
      },
    );

String globalSubsKindLabel(BuildContext context, SubsKind kind) =>
    switch (kind) {
      SubsKind.communities => l(context).globalSubs_kind_communities,
      SubsKind.communityBlocks => l(context).globalSubs_kind_communityBlocks,
      SubsKind.userBlocks => l(context).globalSubs_kind_userBlocks,
    };

/// Signed-in accounts. A Mastodon account's follows of groups stand for
/// communities.
List<String> globalSubsAccounts(AppController ac) => [
  for (final account in ac.accounts.keys)
    if (account.split('@').first.isNotEmpty &&
        ac.servers.containsKey(account.split('@').last))
      account,
];

/// A thin bar under an account's line while a job is working on it.
Widget globalSubsAccountBar(GlobalSubsController subs, String account) {
  final total = subs.accountTotal[account] ?? 0;
  final done = subs.accountDone[account] ?? 0;
  if (!subs.running || total == 0 || done >= total) {
    return const SizedBox.shrink();
  }
  return LinearProgressIndicator(value: done / total);
}

String globalSubsWhen(DateTime t) => t.toLocal().toString().substring(0, 16);

/// Status of the cached subscriptions and the jobs that fill them.
@RoutePage()
class GlobalSubscriptionsScreen extends StatefulWidget {
  const GlobalSubscriptionsScreen({super.key});

  @override
  State<GlobalSubscriptionsScreen> createState() =>
      _GlobalSubscriptionsScreenState();
}

class _GlobalSubscriptionsScreenState extends State<GlobalSubscriptionsScreen> {
  final Set<String> _unchecked = {};

  @override
  void initState() {
    super.initState();
    globalSubsFor(context.read<AppController>()).load();
  }

  String _info(BuildContext context, GlobalSubsController subs, String a) {
    final paused = subs.pausedUntil[a];
    if (paused != null && paused.isAfter(DateTime.now())) {
      return l(
        context,
      ).globalSubs_waiting(globalSubsWhen(paused).substring(11));
    }
    final c = subs.snapshots[SubsKind.communities]![a];
    final cb = subs.snapshots[SubsKind.communityBlocks]![a];
    final ub = subs.snapshots[SubsKind.userBlocks]![a];
    final times = [
      c,
      cb,
      ub,
    ].whereType<AccountSnapshot>().map((e) => e.updated);
    if (times.isEmpty) return l(context).globalSubs_notFetched;
    return l(context).globalSubs_accountInfo(
      c?.subs.length ?? 0,
      cb?.subs.length ?? 0,
      ub?.subs.length ?? 0,
      globalSubsWhen(times.reduce((x, y) => x.isAfter(y) ? x : y)),
    );
  }

  /// Makes [account] match the global list in the chosen lists, after saying
  /// how much that adds and removes.
  Future<void> _replace(
    GlobalSubsController subs,
    String account,
    String which,
  ) async {
    final kinds = switch (which) {
      'subs' => [SubsKind.communities],
      'blocks' => [SubsKind.communityBlocks, SubsKind.userBlocks],
      _ => SubsKind.values,
    };
    if (kinds.every((k) => subs.master[k] == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l(context).globalSubs_noGlobalList)),
      );
      return;
    }
    var adds = 0;
    var removes = 0;
    for (final kind in kinds) {
      final plan = subs.masterPlan(kind, [account])[account];
      adds += plan?.add.length ?? 0;
      removes += plan?.remove.length ?? 0;
    }
    if (adds + removes == 0) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(account),
        content: Text(l(context).globalSubs_replaceConfirm(adds, removes, 1)),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l(context).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l(context).continue_),
          ),
        ],
      ),
    );
    if (ok != true) return;
    subs.applyMaster(kinds, [account]);
  }

  IconData _icon(JobStep? step) => switch (step) {
    JobStep.done => Icons.check_circle_outline,
    JobStep.failed => Icons.error_outline,
    JobStep.cancelled => Icons.cancel_outlined,
    JobStep.running => Icons.sync,
    _ => Icons.schedule,
  };

  @override
  Widget build(BuildContext context) {
    final ac = context.read<AppController>();
    final subs = globalSubsFor(ac);
    final accounts = globalSubsAccounts(ac);
    final chosen = [
      for (final a in accounts)
        if (!_unchecked.contains(a)) a,
    ];

    return Scaffold(
      appBar: AppBar(title: Text(l(context).settings_globalSubscriptions)),
      body: ListenableBuilder(
        listenable: subs,
        builder: (context, _) {
          return ListView(
            children: [
              ListTile(
                leading: const Icon(Icons.cloud_done_outlined),
                title: Text(
                  subs.lastFetched == null
                      ? l(context).globalSubs_notFetched
                      : l(context).globalSubs_fetchedAt(
                          globalSubsWhen(subs.lastFetched!),
                        ),
                ),
                trailing: FilledButton.tonal(
                  onPressed: subs.running || chosen.isEmpty
                      ? null
                      : () => subs.fetchAccounts(chosen),
                  child: Text(l(context).globalSubs_fetchShort),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.save_outlined),
                title: Text(l(context).globalSubs_masterTitle),
                subtitle: subs.master.isEmpty
                    ? Text(l(context).globalSubs_notSaved)
                    : Text(
                        [
                          for (final kind in SubsKind.values)
                            if (subs.master[kind] != null)
                              l(context).globalSubs_masterInfo(
                                globalSubsKindLabel(context, kind),
                                subs.master[kind]!.length,
                                globalSubsWhen(subs.masterUpdated[kind]!),
                              ),
                        ].join('\n'),
                      ),
                isThreeLine: subs.master.length > 1,
                trailing: FilledButton.tonal(
                  onPressed: subs.hasData
                      ? () => context.router.push(
                          const GlobalSubscriptionsListRoute(),
                        )
                      : null,
                  child: Text(l(context).globalSubs_editShort),
                ),
              ),
              if (subs.running) ...[
                ListTile(
                  title: Text(
                    l(context).globalSubs_running(subs.done, subs.total),
                  ),
                  subtitle: Text(l(context).globalSubs_runningHint),
                  trailing: OutlinedButton(
                    onPressed: subs.cancel,
                    child: Text(l(context).cancel),
                  ),
                ),
              ],
              const Divider(),
              for (final account in accounts) ...[
                ListTile(
                  leading: Checkbox(
                    value: !_unchecked.contains(account),
                    onChanged: subs.running
                        ? null
                        : (v) => setState(
                            () => (v ?? false)
                                ? _unchecked.remove(account)
                                : _unchecked.add(account),
                          ),
                  ),
                  title: Text(account),
                  subtitle: Text(_info(context, subs, account)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (subs.steps.containsKey(account))
                        Icon(_icon(subs.steps[account])),
                      PopupMenuButton<String>(
                        enabled: !subs.busy.contains(account),
                        onSelected: (v) => _replace(subs, account, v),
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'subs',
                            child: Text(l(context).globalSubs_replaceSubs),
                          ),
                          PopupMenuItem(
                            value: 'blocks',
                            child: Text(l(context).globalSubs_replaceBlocks),
                          ),
                          PopupMenuItem(
                            value: 'all',
                            child: Text(l(context).globalSubs_replaceAll),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                globalSubsAccountBar(subs, account),
              ],
              if (subs.failures.isNotEmpty && !subs.running)
                ExpansionTile(
                  leading: const Icon(Icons.error_outline),
                  title: Text(
                    l(context).globalSubs_failed(subs.failures.length),
                  ),
                  children: [
                    for (final item in subs.failures)
                      ListTile(title: Text(item)),
                  ],
                ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.compare_arrows),
                title: Text(l(context).globalSubs_compare),
                subtitle: Text(l(context).globalSubs_compare_help),
                enabled: subs.hasData,
                onTap: () => context.router.push(
                  const GlobalSubscriptionsCompareRoute(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
