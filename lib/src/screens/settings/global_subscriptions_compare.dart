import 'package:auto_route/annotations.dart';
import 'package:flutter/material.dart';
import 'package:interstellar/src/controller/controller.dart';
import 'package:interstellar/src/controller/global_subs.dart';
import 'package:interstellar/src/screens/settings/global_subscriptions.dart';
import 'package:interstellar/src/utils/utils.dart';
import 'package:interstellar/src/widgets/account_avatar.dart';
import 'package:provider/provider.dart';

const _cellWidth = 52.0;

/// Every account's cached lists as a table: one row per item, one column per
/// account.
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
  bool _onlyDifferences = true;

  String _cell(String account, String name) => '$account\n$name';

  Future<void> _toggle(String account, String name, bool value) async {
    final subs = globalSubsFor(context.read<AppController>());
    final key = _cell(account, name);
    setState(() => _busy.add(key));
    await subs.setOne(account, _kind, name, value);
    if (mounted) setState(() => _busy.remove(key));
  }

  /// Gives [only] (or every account) what the others have.
  Future<void> _sync(List<String> accounts, {String? only}) async {
    final subs = globalSubsFor(context.read<AppController>());
    final m = subs.matrix(_kind, accounts);
    final count = only == null ? m.missingTotal : m.missing(only).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(only ?? l(context).globalSubs_syncAll),
        content: Text(l(context).globalSubs_syncAll_confirm(count)),
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
    subs.syncMissing(_kind, accounts, only: only);
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
        final rows = [
          for (final name in matrix.communities)
            if (!_onlyDifferences ||
                accounts.any((a) => !matrix.isSubscribed(a, name)))
              name,
        ];
        return Scaffold(
          appBar: AppBar(
            title: Text(l(context).globalSubs_compare),
            actions: [
              IconButton(
                tooltip: l(context).globalSubs_syncAll,
                icon: const Icon(Icons.sync),
                onPressed: subs.running || matrix.missingTotal == 0
                    ? null
                    : () => _sync(accounts),
              ),
            ],
          ),
          // Capped so a wide screen does not strand the boxes far from names.
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                children: [
                  // Scrolls on its own so the table keeps room with many accounts.
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * 0.4,
                    ),
                    child: SingleChildScrollView(
                      child: Column(
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
                              onSelectionChanged: (v) =>
                                  setState(() => _kind = v.first),
                            ),
                          ),
                          if (subs.running) ...[
                            LinearProgressIndicator(
                              value: subs.total == 0
                                  ? null
                                  : subs.done / subs.total,
                            ),
                            ListTile(
                              dense: true,
                              title: Text(
                                l(
                                  context,
                                ).globalSubs_running(subs.done, subs.total),
                              ),
                              trailing: OutlinedButton(
                                onPressed: subs.cancel,
                                child: Text(l(context).cancel),
                              ),
                            ),
                          ],
                          SwitchListTile(
                            dense: true,
                            title: Text(l(context).globalSubs_onlyDifferences),
                            value: _onlyDifferences,
                            onChanged: (v) =>
                                setState(() => _onlyDifferences = v),
                          ),
                          // One line per account: who it is, what it lacks, and a button
                          // that gives it everything the others have.
                          for (final account in accounts)
                            ListTile(
                              dense: true,
                              leading: AccountAvatar(account),
                              title: Text(
                                account,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                l(context).globalSubs_accountCounts(
                                  matrix.communities
                                      .where(
                                        (n) => matrix.isSubscribed(account, n),
                                      )
                                      .length,
                                  matrix.missing(account).length,
                                ),
                              ),
                              trailing: FilledButton.tonal(
                                onPressed:
                                    subs.running ||
                                        matrix.missing(account).isEmpty
                                    ? null
                                    : () => _sync(accounts, only: account),
                                child: Text(
                                  l(context).globalSubs_addMissing(
                                    matrix.missing(account).length,
                                  ),
                                ),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                            child: Text(
                              l(context).globalSubs_tableHint,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Column headers: the same avatars as above.
                  Row(
                    children: [
                      const Spacer(),
                      for (final account in accounts)
                        SizedBox(
                          width: _cellWidth,
                          child: Tooltip(
                            message: account,
                            child: Center(child: AccountAvatar(account)),
                          ),
                        ),
                    ],
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: rows.isEmpty
                        ? Center(child: Text(l(context).globalSubs_empty))
                        : ListView.builder(
                            itemCount: rows.length,
                            itemExtent: 44,
                            itemBuilder: (context, i) {
                              final name = rows[i];
                              return Row(
                                children: [
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.only(left: 16),
                                      child: Text(
                                        name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                  for (final account in accounts)
                                    SizedBox(
                                      width: _cellWidth,
                                      child:
                                          _busy.contains(_cell(account, name))
                                          ? const Center(
                                              child: SizedBox(
                                                width: 18,
                                                height: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              ),
                                            )
                                          : Checkbox(
                                              value: matrix.isSubscribed(
                                                account,
                                                name,
                                              ),
                                              onChanged: subs.running
                                                  ? null
                                                  : (v) => _toggle(
                                                      account,
                                                      name,
                                                      v ?? false,
                                                    ),
                                            ),
                                    ),
                                ],
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
