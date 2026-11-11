import 'package:auto_route/annotations.dart';
import 'package:flutter/material.dart';
import 'package:interstellar/src/controller/controller.dart';
import 'package:interstellar/src/screens/explore/explore_screen.dart';
import 'package:interstellar/src/utils/subscription_matrix.dart';
import 'package:interstellar/src/utils/utils.dart';
import 'package:provider/provider.dart';

/// Every account's community subscriptions side by side.
@RoutePage()
class GlobalSubscriptionsScreen extends StatefulWidget {
  const GlobalSubscriptionsScreen({super.key});

  @override
  State<GlobalSubscriptionsScreen> createState() =>
      _GlobalSubscriptionsScreenState();
}

class _GlobalSubscriptionsScreenState extends State<GlobalSubscriptionsScreen> {
  static const _maxPages = 100;

  SubscriptionMatrix? _matrix;
  final Map<String, Object> _loadErrors = {};
  final Set<String> _busy = {};
  final List<String> _failed = [];
  bool _syncing = false;

  String _cell(String account, String community) => '$account\n$community';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// Accounts that can list communities: signed in, and not Mastodon.
  List<String> _accounts(AppController ac) => [
    for (final account in ac.accounts.keys)
      if (account.split('@').first.isNotEmpty &&
          (ac.servers[account.split('@').last]?.software.canBeAppAccount ??
              false))
        account,
  ];

  Future<void> _load() async {
    final ac = context.read<AppController>();
    final accounts = _accounts(ac);
    setState(() {
      _matrix = null;
      _loadErrors.clear();
    });
    final byAccount = <String, Set<String>>{};
    await Future.wait([
      for (final account in accounts)
        () async {
          try {
            final api = await ac.getApiForAccount(account);
            final host = account.split('@').last;
            final names = <String>{};
            String? page;
            var pages = 0;
            do {
              final res = await api.community.list(
                page: page,
                filter: ExploreFilter.subscribed,
              );
              names.addAll(res.items.map((e) => normalizeName(e.name, host)));
              page = res.nextPage;
            } while (page != null && ++pages < _maxPages);
            byAccount[account] = names;
          } catch (e) {
            _loadErrors[account] = e;
            byAccount[account] = {};
          }
        }(),
    ]);
    if (!mounted) return;
    setState(() {
      // Keeps the account order stable.
      _matrix = SubscriptionMatrix({
        for (final account in accounts) account: byAccount[account] ?? {},
      });
    });
  }

  /// Subscribes or unsubscribes [account] by looking the community up on its
  /// own server. Returns whether it worked.
  Future<bool> _apply(String account, String community, bool state) async {
    final ac = context.read<AppController>();
    final key = _cell(account, community);
    setState(() => _busy.add(key));
    try {
      final api = await ac.getApiForAccount(account);
      final host = account.split('@').last;
      final found = await api.community.getByName(
        denormalizeName(community, host),
      );
      if (found.isUserSubscribed != state) {
        await api.community.subscribe(found.id, state);
      }
      _matrix?.set(account, community, state);
      return true;
    } catch (_) {
      _failed.add('$account: $community');
      return false;
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  Future<void> _syncAll() async {
    final matrix = _matrix;
    if (matrix == null || _syncing) return;
    final todo = [
      for (final account in matrix.accounts)
        for (final community in matrix.missing(account)) (account, community),
    ];
    if (todo.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l(context).globalSubs_syncAll),
        content: Text(l(context).globalSubs_syncAll_confirm(todo.length)),
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
    if (ok != true || !mounted) return;
    setState(() {
      _syncing = true;
      _failed.clear();
    });
    // One at a time, so a long list can't hit a server's rate limit.
    for (final (account, community) in todo) {
      if (!mounted) return;
      await _apply(account, community, true);
    }
    if (mounted) setState(() => _syncing = false);
  }

  @override
  Widget build(BuildContext context) {
    final matrix = _matrix;
    final accounts = matrix?.accounts ?? const <String>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(l(context).settings_globalSubscriptions),
        actions: [
          IconButton(
            tooltip: l(context).globalSubs_syncAll,
            icon: const Icon(Icons.sync),
            onPressed: matrix == null || _syncing || matrix.missingTotal == 0
                ? null
                : _syncAll,
          ),
          IconButton(
            tooltip: l(context).action_refresh,
            icon: const Icon(Icons.refresh),
            onPressed: _syncing ? null : _load,
          ),
        ],
      ),
      body: matrix == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                if (_syncing) const LinearProgressIndicator(),
                for (final account in _loadErrors.keys)
                  ListTile(
                    leading: const Icon(Icons.error_outline),
                    title: Text(account),
                    subtitle: Text(l(context).globalSubs_loadFailed),
                  ),
                if (_failed.isNotEmpty)
                  ExpansionTile(
                    leading: const Icon(Icons.error_outline),
                    title: Text(l(context).globalSubs_failed(_failed.length)),
                    children: [
                      for (final item in _failed) ListTile(title: Text(item)),
                    ],
                  ),
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
                          if (!_loadErrors.containsKey(account))
                            FilterChip(
                              label: Text(account),
                              selected: matrix.isSubscribed(account, community),
                              visualDensity: VisualDensity.compact,
                              onSelected:
                                  _syncing ||
                                      _busy.contains(_cell(account, community))
                                  ? null
                                  : (value) =>
                                        _apply(account, community, value),
                            ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
