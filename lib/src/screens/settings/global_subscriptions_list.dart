import 'package:auto_route/annotations.dart';
import 'package:flutter/material.dart';
import 'package:interstellar/src/api/host_check.dart';
import 'package:interstellar/src/controller/controller.dart';
import 'package:interstellar/src/controller/global_subs.dart';
import 'package:interstellar/src/screens/settings/global_subscriptions.dart';
import 'package:interstellar/src/utils/utils.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

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
    extends State<GlobalSubscriptionsListScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: SubsKind.values.length,
    vsync: this,
  );
  String _search = '';
  final Set<(SubsKind, String)> _selected = {};
  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  int? _checkDone;
  int _checkTotal = 0;
  bool _stopCheck = false;

  /// Asks each server of the global list whether it answers, then shows the
  /// ones that have failed, by kind and longest failing first.
  Future<void> _check(GlobalSubsController subs) async {
    setState(() {
      _checkDone = 0;
      _stopCheck = false;
    });
    await subs.checkHosts(
      probeHost,
      onProgress: (done, total) {
        if (mounted) {
          setState(() {
            _checkDone = done;
            _checkTotal = total;
          });
        }
      },
      cancelled: () => _stopCheck,
    );
    if (!mounted) return;
    final stopped = _stopCheck;
    setState(() => _checkDone = null);
    if (stopped) return;
    if (subs.problems.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l(context).globalSubs_checkNone)));
      return;
    }
    await _review(subs);
  }

  bool _alsoRemove = true;

  /// Shows the failing servers to mark dead. After each purge it shows what is
  /// left, so several rounds need no new check; Cancel ends it.
  Future<void> _review(GlobalSubsController subs) async {
    while (mounted && subs.problems.isNotEmpty) {
      final marked = await _problemsDialog(subs);
      if (marked == null || marked.isEmpty) return;
      await subs.purge(marked, removeFromAccounts: _alsoRemove);
      if (mounted) setState(_selected.clear);
    }
  }

  Future<Set<String>?> _problemsDialog(GlobalSubsController subs) =>
      showDialog<Set<String>>(
        context: context,
        builder: (context) {
          final chosen = <String>{};
          return StatefulBuilder(
            builder: (context, setLocal) => AlertDialog(
              title: Text(l(context).globalSubs_checkServers),
              content: SizedBox(
                width: 480,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    Text(l(context).globalSubs_checkFound),
                    for (final kind in HostFailure.values) ...[
                      ..._section(context, subs, kind, chosen, setLocal),
                    ],
                    const Divider(),
                    _alsoRemoveTile(
                      context,
                      subs.heldOnAccounts(chosen),
                      _alsoRemove,
                      (v) => setLocal(() => _alsoRemove = v),
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
                  onPressed: chosen.isEmpty
                      ? null
                      : () => Navigator.pop(context, chosen),
                  child: Text(l(context).globalSubs_markDead(chosen.length)),
                ),
              ],
            ),
          );
        },
      );

  Widget _alsoRemoveTile(
    BuildContext context,
    int count,
    bool value,
    void Function(bool) onChanged,
  ) => CheckboxListTile(
    dense: true,
    controlAffinity: ListTileControlAffinity.leading,
    contentPadding: EdgeInsets.zero,
    value: value && count > 0,
    onChanged: count == 0 ? null : (v) => onChanged(v ?? false),
    title: Text(l(context).globalSubs_alsoRemove(count)),
  );

  /// Marks the servers of the selected entries dead, after listing them.
  Future<void> _purgeSelected(GlobalSubsController subs) async {
    final hosts = {for (final (_, n) in _selected) n.split('@').last}.toList()
      ..sort();
    var alsoRemove = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(l(context).globalSubs_purgeServers),
          content: SizedBox(
            width: 480,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final h in hosts)
                  Text(l(context).globalSubs_hostEntries(h, subs.entriesOn(h))),
                const Divider(),
                _alsoRemoveTile(
                  context,
                  subs.heldOnAccounts(hosts.toSet()),
                  alsoRemove,
                  (v) => setLocal(() => alsoRemove = v),
                ),
              ],
            ),
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l(context).cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l(context).globalSubs_markDead(hosts.length)),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await subs.purge(hosts, removeFromAccounts: alsoRemove);
    if (mounted) setState(_selected.clear);
  }

  /// The failing servers of one kind, longest failing first.
  List<Widget> _section(
    BuildContext context,
    GlobalSubsController subs,
    HostFailure kind,
    Set<String> chosen,
    void Function(VoidCallback) setLocal,
  ) {
    final hosts =
        [
          for (final e in subs.problems.entries)
            if (e.value.kind == kind) e.key,
        ]..sort((x, y) {
          final c = subs.problems[y]!.checks.compareTo(
            subs.problems[x]!.checks,
          );
          return c != 0 ? c : x.compareTo(y);
        });
    if (hosts.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(switch (kind) {
          HostFailure.network => l(context).globalSubs_failNetwork,
          HostFailure.http => l(context).globalSubs_failHttp,
          HostFailure.notFediverse => l(context).globalSubs_failNotFediverse,
        }, style: Theme.of(context).textTheme.titleSmall),
      ),
      for (final h in hosts)
        CheckboxListTile(
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          value: chosen.contains(h),
          onChanged: (v) =>
              setLocal(() => (v ?? false) ? chosen.add(h) : chosen.remove(h)),
          title: Text(l(context).globalSubs_hostEntries(h, subs.entriesOn(h))),
          subtitle: Text(
            l(context).globalSubs_failSince(
              subs.problems[h]!.checks,
              globalSubsWhen(subs.problems[h]!.since).substring(0, 10),
              subs.problems[h]!.detail,
            ),
          ),
          secondary: IconButton(
            tooltip: l(context).globalSubs_openInBrowser,
            icon: const Icon(Icons.open_in_new),
            onPressed: () =>
                launchUrl(Uri.https(h), mode: LaunchMode.externalApplication),
          ),
        ),
    ];
  }

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

  /// The dead servers, each of which can be brought back.
  Future<void> _dead(GlobalSubsController subs) => showDialog<void>(
    context: context,
    builder: (context) => ListenableBuilder(
      listenable: subs,
      builder: (context, _) {
        final hosts = subs.dead.toList()..sort();
        return AlertDialog(
          title: Text(l(context).globalSubs_dead),
          content: SizedBox(
            width: 480,
            child: ListView(
              shrinkWrap: true,
              children: [
                Text(l(context).globalSubs_deadHelp),
                if (hosts.isEmpty) Text(l(context).globalSubs_noDead),
                for (final h in hosts)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(h),
                    trailing: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => subs.setDead(hosts.where((x) => x != h)),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l(context).continue_),
            ),
          ],
        );
      },
    ),
  );

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
        // The entries of each list that match the search.
        final shown = <SubsKind, List<String>>{
          for (final kind in SubsKind.values)
            kind: [
              for (final n in [
                ...?subs.master[kind],
              ]..sort((x, y) => x.toLowerCase().compareTo(y.toLowerCase())))
                if (query.isEmpty || n.toLowerCase().contains(query)) n,
            ],
        };
        return Scaffold(
          appBar: AppBar(
            title: Text(l(context).globalSubs_masterTitle),
            actions: [
              IconButton(
                tooltip: l(context).globalSubs_dead,
                icon: const Icon(Icons.block),
                onPressed: () => _dead(subs),
              ),
              if (_selected.isNotEmpty)
                IconButton(
                  tooltip: l(context).globalSubs_purgeServers,
                  icon: const Icon(Icons.dns_outlined),
                  onPressed: () => _purgeSelected(subs),
                ),
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
                        onPressed: subs.master.isEmpty || _checkDone != null
                            ? null
                            : () => _check(subs),
                        child: Text(l(context).globalSubs_checkServers),
                      ),
                      if (subs.problems.isNotEmpty)
                        OutlinedButton(
                          onPressed: () => _review(subs),
                          child: Text(
                            l(
                              context,
                            ).globalSubs_reviewFailing(subs.problems.length),
                          ),
                        ),
                      OutlinedButton(
                        onPressed: subs.master.isEmpty
                            ? null
                            : () => _add(subs),
                        child: Text(l(context).globalSubs_addEntry),
                      ),
                    ],
                  ),
                  if (_checkDone != null)
                    ListTile(
                      dense: true,
                      title: Text(
                        l(
                          context,
                        ).globalSubs_checking(_checkDone!, _checkTotal),
                      ),
                      subtitle: LinearProgressIndicator(
                        value: _checkTotal == 0
                            ? null
                            : _checkDone! / _checkTotal,
                      ),
                      trailing: OutlinedButton(
                        onPressed: () => _stopCheck = true,
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
                  TabBar(
                    controller: _tabs,
                    tabs: [
                      for (final kind in SubsKind.values)
                        Tab(
                          text:
                              '${globalSubsKindLabel(context, kind)} '
                              '(${shown[kind]!.length})',
                        ),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabs,
                      children: [
                        for (final kind in SubsKind.values)
                          subs.master[kind] == null
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Text(
                                      l(context).globalSubs_masterNone,
                                    ),
                                  ),
                                )
                              : Column(
                                  children: [
                                    ListTile(
                                      dense: true,
                                      title: Text(
                                        l(context).globalSubs_masterInfo(
                                          globalSubsKindLabel(context, kind),
                                          subs.master[kind]!.length,
                                          globalSubsWhen(
                                            subs.masterUpdated[kind]!,
                                          ),
                                        ),
                                      ),
                                      trailing: shown[kind]!.isEmpty
                                          ? null
                                          : TextButton(
                                              onPressed: () => setState(() {
                                                final all = {
                                                  for (final n in shown[kind]!)
                                                    (kind, n),
                                                };
                                                _selected.containsAll(all)
                                                    ? _selected.removeAll(all)
                                                    : _selected.addAll(all);
                                              }),
                                              child: Text(
                                                _selected.containsAll({
                                                      for (final n
                                                          in shown[kind]!)
                                                        (kind, n),
                                                    })
                                                    ? l(
                                                        context,
                                                      ).globalSubs_selectNone
                                                    : l(
                                                        context,
                                                      ).globalSubs_selectAll,
                                              ),
                                            ),
                                    ),
                                    Expanded(
                                      child: ListView.builder(
                                        itemCount: shown[kind]!.length,
                                        itemExtent: 44,
                                        itemBuilder: (context, i) {
                                          final name = shown[kind]![i];
                                          return CheckboxListTile(
                                            dense: true,
                                            controlAffinity:
                                                ListTileControlAffinity.leading,
                                            title: Text(
                                              name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            value: _selected.contains((
                                              kind,
                                              name,
                                            )),
                                            onChanged: (v) => setState(
                                              () => (v ?? false)
                                                  ? _selected.add((kind, name))
                                                  : _selected.remove((
                                                      kind,
                                                      name,
                                                    )),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                      ],
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
