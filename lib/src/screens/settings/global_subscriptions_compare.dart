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
  String _search = '';

  String _cell(String account, String name) => '$account\n$name';

  Future<void> _toggle(String account, String name, bool value) async {
    final subs = globalSubsFor(context.read<AppController>());
    final key = _cell(account, name);
    setState(() => _busy.add(key));
    await subs.setOne(account, _kind, name, value);
    if (mounted) setState(() => _busy.remove(key));
  }

  /// Makes [account] match the account the user picks.
  Future<void> _matchAnother(List<String> accounts, String account) async {
    final source = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l(context).globalSubs_pickSource),
        children: [
          for (final a in accounts)
            if (a != account)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, a),
                child: Row(
                  spacing: 8,
                  children: [
                    AccountAvatar(a),
                    Flexible(child: Text(a, overflow: TextOverflow.ellipsis)),
                  ],
                ),
              ),
        ],
      ),
    );
    if (source == null || !mounted) return;
    await _confirmReplace(source, [account]);
  }

  /// Makes every account in [targets] (but the source) match [source], after
  /// saying how much that adds and removes.
  Future<void> _confirmReplace(String source, List<String> targets) async {
    final subs = globalSubsFor(context.read<AppController>());
    final plan = subs.replacePlan(_kind, source, targets);
    if (plan.isEmpty) return;
    final adds = plan.values.fold(0, (n, v) => n + v.add.length);
    final removes = plan.values.fold(0, (n, v) => n + v.remove.length);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(source),
        content: Text(
          l(context).globalSubs_replaceConfirm(adds, removes, plan.length),
        ),
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
    subs.replaceLists(_kind, source, targets);
  }

  /// Removes every entry of the list from one account, after asking.
  Future<void> _clear(String account) async {
    final subs = globalSubsFor(context.read<AppController>());
    final names = [...?subs.snapshots[_kind]![account]?.subs];
    if (names.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(account),
        content: Text(l(context).globalSubs_clearConfirm(names.length)),
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
    subs.setMany(_kind, names, [account], false);
  }

  /// Tapping a name: add or remove it on every account.
  Future<void> _nameMenu(List<String> accounts, String name) async {
    final subs = globalSubsFor(context.read<AppController>());
    final state = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(name), dense: true),
            ListTile(
              leading: const Icon(Icons.add),
              title: Text(l(context).globalSubs_addToAll),
              onTap: () => Navigator.pop(context, true),
            ),
            ListTile(
              leading: const Icon(Icons.remove),
              title: Text(l(context).globalSubs_removeFromAll),
              onTap: () => Navigator.pop(context, false),
            ),
          ],
        ),
      ),
    );
    if (state == null) return;
    subs.setMany(_kind, [name], accounts, state);
  }

  /// Adds or removes every listed row on all accounts, after asking.
  Future<void> _batch(
    List<String> accounts,
    List<String> names,
    bool state,
  ) async {
    final subs = globalSubsFor(context.read<AppController>());
    final m = subs.matrix(_kind, accounts);
    final count = [
      for (final a in accounts)
        for (final n in names)
          if (m.isSubscribed(a, n) != state) n,
    ].length;
    if (count == 0) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          state
              ? l(context).globalSubs_addResultsToAll(names.length)
              : l(context).globalSubs_removeResultsFromAll(names.length),
        ),
        content: Text(l(context).globalSubs_syncAll_confirm(count)),
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
    subs.setMany(_kind, names, accounts, state);
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
        final query = _search.trim().toLowerCase();
        // A search shows every match, even ones all accounts already agree on.
        final rows = [
          for (final name in matrix.communities)
            if (query.isNotEmpty
                ? name.toLowerCase().contains(query)
                : !_onlyDifferences ||
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
              PopupMenuButton<bool>(
                enabled: !subs.running && rows.isNotEmpty,
                onSelected: (state) => _batch(accounts, rows, state),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: true,
                    child: Text(
                      l(context).globalSubs_addResultsToAll(rows.length),
                    ),
                  ),
                  PopupMenuItem(
                    value: false,
                    child: Text(
                      l(context).globalSubs_removeResultsFromAll(rows.length),
                    ),
                  ),
                ],
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
                          if (subs.failures.isNotEmpty)
                            ExpansionTile(
                              dense: true,
                              leading: const Icon(Icons.error_outline),
                              title: Text(
                                l(
                                  context,
                                ).globalSubs_failed(subs.failures.length),
                              ),
                              children: [
                                for (final f in subs.failures)
                                  ListTile(dense: true, title: Text(f)),
                              ],
                            ),
                          SwitchListTile(
                            dense: true,
                            title: Text(l(context).globalSubs_onlyDifferences),
                            value: _onlyDifferences,
                            onChanged: (v) =>
                                setState(() => _onlyDifferences = v),
                          ),
                          // One line per account: who it is, what it lacks, and a button
                          // that gives it everything the others have.
                          for (final account in accounts) ...[
                            ListTile(
                              dense: true,
                              leading: AccountAvatar(account),
                              title: Text(
                                account,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                subs.running &&
                                        (subs.accountTotal[account] ?? 0) > 0
                                    ? l(context).globalSubs_running(
                                        subs.accountDone[account] ?? 0,
                                        subs.accountTotal[account]!,
                                      )
                                    : l(context).globalSubs_accountCounts(
                                        matrix.communities
                                            .where(
                                              (n) => matrix.isSubscribed(
                                                account,
                                                n,
                                              ),
                                            )
                                            .length,
                                        matrix.missing(account).length,
                                      ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  FilledButton.tonal(
                                    onPressed:
                                        subs.busy.contains(account) ||
                                            matrix.missing(account).isEmpty
                                        ? null
                                        : () => _sync(accounts, only: account),
                                    child: Text(
                                      l(context).globalSubs_addMissing(
                                        matrix.missing(account).length,
                                      ),
                                    ),
                                  ),
                                  PopupMenuButton<String>(
                                    enabled: !subs.busy.contains(account),
                                    onSelected: (v) => switch (v) {
                                      'match' => _matchAnother(
                                        accounts,
                                        account,
                                      ),
                                      'copy' => _confirmReplace(
                                        account,
                                        accounts,
                                      ),
                                      _ => _clear(account),
                                    },
                                    itemBuilder: (context) => [
                                      PopupMenuItem(
                                        value: 'match',
                                        child: Text(
                                          l(context).globalSubs_matchAnother,
                                        ),
                                      ),
                                      PopupMenuItem(
                                        value: 'copy',
                                        child: Text(
                                          l(context).globalSubs_copyToOthers,
                                        ),
                                      ),
                                      PopupMenuItem(
                                        value: 'clear',
                                        child: Text(
                                          l(context).globalSubs_clearList(
                                            subs
                                                    .snapshots[_kind]![account]
                                                    ?.subs
                                                    .length ??
                                                0,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            globalSubsAccountBar(subs, account),
                          ],
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
                  // Outside the scrolling part, so Cancel never scrolls away.
                  if (subs.running)
                    ListTile(
                      dense: true,
                      title: Text(
                        l(context).globalSubs_running(subs.done, subs.total),
                      ),
                      trailing: OutlinedButton(
                        onPressed: subs.cancel,
                        child: Text(l(context).cancel),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: TextField(
                      decoration: InputDecoration(
                        isDense: true,
                        prefixIcon: const Icon(Icons.search),
                        hintText: l(context).globalSubs_search,
                      ),
                      onChanged: (v) => setState(() => _search = v),
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
                                    child: InkWell(
                                      onTap: subs.running
                                          ? null
                                          : () => _nameMenu(accounts, name),
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Padding(
                                          padding: const EdgeInsets.only(
                                            left: 16,
                                          ),
                                          child: Text(
                                            name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
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
                                              onChanged:
                                                  subs.busy.contains(account)
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
