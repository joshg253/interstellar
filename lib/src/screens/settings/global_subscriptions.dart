import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:interstellar/src/controller/controller.dart';
import 'package:interstellar/src/controller/global_subs.dart';
import 'package:interstellar/src/controller/router.gr.dart';
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
      fetch: (account, cancelled) async {
        final api = await ac.getApiForAccount(account);
        final host = account.split('@').last;
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
      },
      apply: (account, community, state) async {
        final api = await ac.getApiForAccount(account);
        final host = account.split('@').last;
        final found = await api.community.getByName(
          denormalizeName(community, host),
        );
        if (found.isUserSubscribed != state) {
          await api.community.subscribe(found.id, state);
        }
      },
    );

/// Accounts that can list communities: signed in, and not Mastodon.
List<String> globalSubsAccounts(AppController ac) => [
  for (final account in ac.accounts.keys)
    if (account.split('@').first.isNotEmpty &&
        (ac.servers[account.split('@').last]?.software.canBeAppAccount ??
            false))
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
          final master = subs.master;
          return ListView(
            children: [
              ListTile(
                leading: const Icon(Icons.save_outlined),
                title: Text(
                  master == null
                      ? l(context).globalSubs_notSaved
                      : l(context).globalSubs_saved(
                          master.length,
                          globalSubsWhen(subs.masterUpdated!),
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
                          () => v == true
                              ? _unchecked.remove(account)
                              : _unchecked.add(account),
                        ),
                  secondary: subs.steps.containsKey(account)
                      ? Icon(_icon(subs.steps[account]))
                      : null,
                  title: Text(account),
                  subtitle: Text(
                    subs.snapshots[account] == null
                        ? l(context).globalSubs_notFetched
                        : l(context).globalSubs_accountInfo(
                            subs.snapshots[account]!.subs.length,
                            globalSubsWhen(subs.snapshots[account]!.updated),
                          ),
                  ),
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
                enabled: !subs.running && subs.snapshots.isNotEmpty,
                onTap: subs.saveMerged,
              ),
              ListTile(
                leading: const Icon(Icons.compare_arrows),
                title: Text(l(context).globalSubs_compare),
                subtitle: Text(l(context).globalSubs_compare_help),
                enabled: subs.snapshots.isNotEmpty,
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
