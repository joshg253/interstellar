import 'package:auto_route/annotations.dart';
import 'package:flutter/material.dart';
import 'package:interstellar/src/controller/controller.dart';
import 'package:interstellar/src/controller/global_subs.dart';
import 'package:interstellar/src/screens/settings/global_subscriptions.dart';
import 'package:interstellar/src/utils/utils.dart';
import 'package:interstellar/src/widgets/account_avatar.dart';
import 'package:provider/provider.dart';

/// The one saved list per kind: edit it, then make accounts match it.
@RoutePage()
class GlobalSubscriptionsListScreen extends StatefulWidget {
  const GlobalSubscriptionsListScreen({super.key});

  @override
  State<GlobalSubscriptionsListScreen> createState() =>
      _GlobalSubscriptionsListScreenState();
}

class _GlobalSubscriptionsListScreenState
    extends State<GlobalSubscriptionsListScreen> {
  SubsKind _kind = SubsKind.communities;
  String _search = '';
  final Set<String> _selected = {};

  Future<bool> _ask(String title, String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(text),
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
      ) ??
      false;

  Future<void> _rebuild(GlobalSubsController subs) async {
    if (subs.master[_kind] != null &&
        !await _ask(
          l(context).globalSubs_rebuild,
          l(context).globalSubs_rebuildConfirm,
        )) {
      return;
    }
    await subs.rebuildMaster(_kind);
    if (mounted) setState(_selected.clear);
  }

  Future<void> _add(GlobalSubsController subs) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l(context).globalSubs_addEntry),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'name@server.example'),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l(context).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(l(context).continue_),
          ),
        ],
      ),
    );
    // A name needs its server: the same name can be on many.
    if (name == null || !name.contains('@') || name.startsWith('@')) return;
    await subs.editMaster(_kind, add: [name.toLowerCase()]);
  }

  Future<void> _apply(GlobalSubsController subs, List<String> accounts) async {
    final chosen = {...accounts};
    final targets = await showDialog<List<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(l(context).globalSubs_applyTo),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final a in accounts)
                  CheckboxListTile(
                    dense: true,
                    secondary: AccountAvatar(a),
                    title: Text(a, overflow: TextOverflow.ellipsis),
                    value: chosen.contains(a),
                    onChanged: (v) => setLocal(
                      () => (v ?? false) ? chosen.add(a) : chosen.remove(a),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l(context).cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, chosen.toList()),
              child: Text(l(context).continue_),
            ),
          ],
        ),
      ),
    );
    if (targets == null || targets.isEmpty || !mounted) return;
    final plan = subs.masterPlan(_kind, targets);
    if (plan.isEmpty) return;
    final adds = plan.values.fold(0, (n, v) => n + v.add.length);
    final removes = plan.values.fold(0, (n, v) => n + v.remove.length);
    if (!await _ask(
      l(context).globalSubs_applyTo,
      l(context).globalSubs_replaceConfirm(adds, removes, plan.length),
    )) {
      return;
    }
    subs.applyMaster(_kind, targets);
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
        final master = subs.master[_kind];
        final query = _search.trim().toLowerCase();
        final rows = [
          for (final n in [
            ...?master,
          ]..sort((x, y) => x.toLowerCase().compareTo(y.toLowerCase())))
            if (query.isEmpty || n.toLowerCase().contains(query)) n,
        ];
        return Scaffold(
          appBar: AppBar(
            title: Text(l(context).globalSubs_masterTitle),
            actions: [
              if (_selected.isNotEmpty)
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline),
                  label: Text(
                    l(context).globalSubs_removeSelected(_selected.length),
                  ),
                  onPressed: () async {
                    await subs.editMaster(_kind, remove: _selected);
                    if (mounted) setState(_selected.clear);
                  },
                ),
            ],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
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
                      onSelectionChanged: (v) => setState(() {
                        _kind = v.first;
                        _selected.clear();
                      }),
                    ),
                  ),
                  ListTile(
                    dense: true,
                    title: Text(
                      master == null
                          ? l(context).globalSubs_masterNone
                          : l(context).globalSubs_masterInfo(
                              master.length,
                              globalSubsWhen(subs.masterUpdated[_kind]!),
                            ),
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: subs.running || accounts.isEmpty
                            ? null
                            : () => _rebuild(subs),
                        child: Text(l(context).globalSubs_rebuild),
                      ),
                      OutlinedButton(
                        onPressed: () => _add(subs),
                        child: Text(l(context).globalSubs_addEntry),
                      ),
                      FilledButton(
                        onPressed:
                            subs.running || master == null || accounts.isEmpty
                            ? null
                            : () => _apply(subs, accounts),
                        child: Text(l(context).globalSubs_applyTo),
                      ),
                    ],
                  ),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    child: TextField(
                      decoration: InputDecoration(
                        isDense: true,
                        prefixIcon: const Icon(Icons.search),
                        hintText: l(context).globalSubs_search,
                      ),
                      onChanged: (v) => setState(() => _search = v),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: rows.length,
                      itemExtent: 44,
                      itemBuilder: (context, i) {
                        final name = rows[i];
                        return CheckboxListTile(
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          value: _selected.contains(name),
                          onChanged: (v) => setState(
                            () => (v ?? false)
                                ? _selected.add(name)
                                : _selected.remove(name),
                          ),
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
