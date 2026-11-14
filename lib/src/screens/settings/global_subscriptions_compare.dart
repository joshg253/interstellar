import 'package:auto_route/annotations.dart';
import 'package:flutter/material.dart';
import 'package:interstellar/src/controller/controller.dart';
import 'package:interstellar/src/controller/global_subs.dart';
import 'package:interstellar/src/screens/settings/global_subscriptions.dart';
import 'package:interstellar/src/utils/utils.dart';
import 'package:provider/provider.dart';

/// Every account's cached community subscriptions side by side.
@RoutePage()
class GlobalSubscriptionsCompareScreen extends StatefulWidget {
  const GlobalSubscriptionsCompareScreen({super.key});

  @override
  State<GlobalSubscriptionsCompareScreen> createState() =>
      _GlobalSubscriptionsCompareScreenState();
}

class _GlobalSubscriptionsCompareScreenState
    extends State<GlobalSubscriptionsCompareScreen> {
  final Set<String> _busy = {};
  SubsKind _kind = SubsKind.communities;

  String _cell(String account, String community) => '$account\n$community';

  Future<void> _toggle(String account, String community, bool value) async {
    final subs = globalSubsFor(context.read<AppController>());
    final key = _cell(account, community);
    setState(() => _busy.add(key));
    await subs.setOne(account, _kind, community, value);
    if (mounted) setState(() => _busy.remove(key));
  }

  Future<void> _syncAll(List<String> accounts) async {
    final subs = globalSubsFor(context.read<AppController>());
    final m = subs.matrix(_kind, accounts);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l(context).globalSubs_syncAll),
        content: Text(l(context).globalSubs_syncAll_confirm(m.missingTotal)),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l(context).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l(context).globalSubs_syncAll),
          ),
        ],
      ),
    );
    if (ok != true) return;
    // Runs in the background; progress shows here and on the status screen.
    subs.syncMissing(_kind, accounts);
  }

  @override
  Widget build(BuildContext context) {
    final ac = context.read<AppController>();
    final subs = globalSubsFor(ac);
    final accounts = [
      for (final a in globalSubsAccounts(ac))
        if (subs.snapshots[_kind]!.containsKey(a)) a,
    ];

    return ListenableBuilder(
      listenable: subs,
      builder: (context, _) {
        final matrix = subs.matrix(_kind, accounts);
        return Scaffold(
          appBar: AppBar(
            title: Text(l(context).globalSubs_compare),
            actions: [
              IconButton(
                tooltip: l(context).globalSubs_syncAll,
                icon: const Icon(Icons.sync),
                onPressed: subs.running || matrix.missingTotal == 0
                    ? null
                    : () => _syncAll(accounts),
              ),
            ],
          ),
          body: ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: SegmentedButton<SubsKind>(
                  showSelectedIcon: false,
                  segments: [
                    for (final kind in SubsKind.values)
                      ButtonSegment(
                        value: kind,
                        label: Text(
                          globalSubsKindLabel(context, kind),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  selected: {_kind},
                  onSelectionChanged: (v) => setState(() => _kind = v.first),
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
                  trailing: OutlinedButton(
                    onPressed: subs.cancel,
                    child: Text(l(context).cancel),
                  ),
                ),
              ],
              if (matrix.communities.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(l(context).globalSubs_empty),
                ),
              for (final community in matrix.communities)
                ListTile(
                  title: Text(community),
                  subtitle: Wrap(
                    spacing: 6,
                    children: [
                      for (final account in accounts)
                        FilterChip(
                          label: Text(account),
                          selected: matrix.isSubscribed(account, community),
                          visualDensity: VisualDensity.compact,
                          onSelected:
                              subs.running ||
                                  _busy.contains(_cell(account, community))
                              ? null
                              : (value) => _toggle(account, community, value),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
