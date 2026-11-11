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
            return listBlocked(api, host, users: false);
          case SubsKind.userBlocks:
            return listBlocked(api, host, users: true);
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
              if (subs.master.isEmpty)
                ListTile(
                  leading: const Icon(Icons.save_outlined),
                  title: Text(l(context).globalSubs_notSaved),
                ),
              for (final kind in SubsKind.values)
                if (subs.master[kind] != null)
                  ListTile(
                    leading: const Icon(Icons.save_outlined),
                    title: Text(
                      l(context).globalSubs_saved(
                        globalSubsKindLabel(context, kind),
                        subs.master[kind]!.length,
                        globalSubsWhen(subs.masterUpdated[kind]!),
                      ),
                    ),
                  ),
              if (subs.running) ...[
                LinearProgressIndicator(
                  value: subs.total == 0 ? null : subs.done / subs.total,
                ),
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
              for (final account in accounts)
                CheckboxListTile(
                  value: !_unchecked.contains(account),
                  onChanged: subs.running
                      ? null
                      : (v) => setState(
                          () => (v ?? false)
                              ? _unchecked.remove(account)
                              : _unchecked.add(account),
                        ),
                  secondary: subs.steps.containsKey(account)
                      ? Icon(_icon(subs.steps[account]))
                      : null,
                  title: Text(account),
                  subtitle: Text(_info(context, subs, account)),
                ),
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
                leading: const Icon(Icons.cloud_download_outlined),
                title: Text(l(context).globalSubs_fetch),
                subtitle: Text(l(context).globalSubs_fetch_help),
                enabled: !subs.running && chosen.isNotEmpty,
                onTap: () => subs.fetchAccounts(chosen),
              ),
              ListTile(
                leading: const Icon(Icons.merge_type),
                title: Text(l(context).globalSubs_saveMerged),
                subtitle: Text(l(context).globalSubs_saveMerged_help),
                enabled: !subs.running && subs.hasData,
                onTap: subs.saveMerged,
              ),
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
