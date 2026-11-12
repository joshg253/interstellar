import 'package:auto_route/annotations.dart';
import 'package:flutter/material.dart';
import 'package:interstellar/src/controller/controller.dart';
import 'package:interstellar/src/controller/global_subs.dart';
import 'package:interstellar/src/screens/settings/global_subscriptions.dart';
import 'package:interstellar/src/utils/utils.dart';
import 'package:provider/provider.dart';

/// The one saved list (subscriptions, blocked communities, blocked users) to
/// edit. Accounts are made to match it from the main screen.
@RoutePage()
class GlobalSubscriptionsListScreen extends StatefulWidget {
  const GlobalSubscriptionsListScreen({super.key});

  @override
  State<GlobalSubscriptionsListScreen> createState() =>
      _GlobalSubscriptionsListScreenState();
}

class _GlobalSubscriptionsListScreenState
    extends State<GlobalSubscriptionsListScreen> {
  String _search = '';
  final Set<(SubsKind, String)> _selected = {};

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
    if (subs.master.isNotEmpty &&
        !await _ask(
          l(context).globalSubs_rebuild,
          l(context).globalSubs_rebuildConfirm,
        )) {
      return;
    }
    await subs.rebuildAllMasters();
    if (mounted) setState(_selected.clear);
  }

  Future<void> _add(GlobalSubsController subs) async {
    final controller = TextEditingController();
    var kind = SubsKind.communities;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(l(context).globalSubs_addEntry),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<SubsKind>(
                isExpanded: true,
                value: kind,
                items: [
                  for (final k in SubsKind.values)
                    DropdownMenuItem(
                      value: k,
                      child: Text(globalSubsKindLabel(context, k)),
                    ),
                ],
                onChanged: (v) => setLocal(() => kind = v ?? kind),
              ),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'name@server.example',
                ),
              ),
            ],
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
      ),
    );
    // A name needs its server: the same name can be on many.
    if (name == null || !name.contains('@') || name.startsWith('@')) return;
    await subs.editMaster(kind, add: [name.toLowerCase()]);
  }

  @override
  Widget build(BuildContext context) {
    final subs = globalSubsFor(context.read<AppController>());

    return ListenableBuilder(
      listenable: subs,
      builder: (context, _) {
        final query = _search.trim().toLowerCase();
        // A header row per list, then its entries.
        final rows = <(SubsKind, String?)>[];
        for (final kind in SubsKind.values) {
          final names = [...?subs.master[kind]]
            ..sort((x, y) => x.toLowerCase().compareTo(y.toLowerCase()));
          final shown = [
            for (final n in names)
              if (query.isEmpty || n.toLowerCase().contains(query)) n,
          ];
          if (subs.master[kind] == null) continue;
          rows
            ..add((kind, null))
            ..addAll([for (final n in shown) (kind, n)]);
        }
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
                    for (final kind in SubsKind.values) {
                      await subs.editMaster(
                        kind,
                        remove: [
                          for (final (k, n) in _selected)
                            if (k == kind) n,
                        ],
                      );
                    }
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
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: subs.running || !subs.hasData
                            ? null
                            : () => _rebuild(subs),
                        child: Text(l(context).globalSubs_rebuild),
                      ),
                      OutlinedButton(
                        onPressed: subs.master.isEmpty
                            ? null
                            : () => _add(subs),
                        child: Text(l(context).globalSubs_addEntry),
                      ),
                    ],
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
                    child: rows.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(l(context).globalSubs_masterNone),
                            ),
                          )
                        : ListView.builder(
                            itemCount: rows.length,
                            itemExtent: 44,
                            itemBuilder: (context, i) {
                              final (kind, name) = rows[i];
                              if (name == null) {
                                return ListTile(
                                  dense: true,
                                  tileColor: Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerHighest,
                                  title: Text(
                                    l(context).globalSubs_masterInfo(
                                      globalSubsKindLabel(context, kind),
                                      subs.master[kind]!.length,
                                      globalSubsWhen(subs.masterUpdated[kind]!),
                                    ),
                                  ),
                                );
                              }
                              return CheckboxListTile(
                                dense: true,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                title: Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                value: _selected.contains((kind, name)),
                                onChanged: (v) => setState(
                                  () => (v ?? false)
                                      ? _selected.add((kind, name))
                                      : _selected.remove((kind, name)),
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
