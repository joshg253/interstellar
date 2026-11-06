import 'package:flutter/material.dart';
import 'package:interstellar/src/controller/controller.dart';
import 'package:interstellar/src/controller/server.dart';
import 'package:interstellar/src/models/community.dart';
import 'package:interstellar/src/screens/explore/explore_screen.dart'
    show ExploreFilter;
import 'package:interstellar/src/widgets/account_avatar.dart';
import 'package:interstellar/src/widgets/avatar.dart';

/// Identity of a community across servers, `name@host`. Taken from the
/// ActivityPub id when there is one (the host plus the last path segment, which
/// covers Lemmy/PieFed `/c/name` and mbin `/m/name`), else from the name,
/// adding the account's own host when the name is bare.
String communityKey(String? apId, String name, String accountHost) {
  final uri = apId == null ? null : Uri.tryParse(apId);
  if (uri != null && uri.host.isNotEmpty && uri.pathSegments.isNotEmpty) {
    return '${uri.pathSegments.last.toLowerCase()}@${uri.host.toLowerCase()}';
  }
  final lower = name.toLowerCase();
  return lower.contains('@') ? lower : '$lower@${accountHost.toLowerCase()}';
}

/// One item as seen by every account that has it.
class Union<T> {
  Union(this.key);

  final String key;

  /// account -> that account's copy, in the order accounts were given.
  final Map<String, T> byAccount = {};

  T get first => byAccount.values.first;
}

/// Merges per-account lists into one list of [Union]s by [keyOf], which is
/// told which account an item came from.
List<Union<T>> unionByKey<T>(
  Map<String, List<T>> perAccount,
  String Function(String account, T item) keyOf,
) {
  final byKey = <String, Union<T>>{};
  for (final entry in perAccount.entries) {
    for (final item in entry.value) {
      final key = keyOf(entry.key, item);
      byKey.putIfAbsent(key, () => Union<T>(key))
        ..byAccount.putIfAbsent(entry.key, () => item);
    }
  }
  return byKey.values.toList();
}

typedef GlobalCommunity = Union<DetailedCommunityModel>;

/// Every subscribed community of every signed-in account, unified. Accounts
/// that fail (or can't list subscriptions) are left out and reported.
Future<({List<GlobalCommunity> communities, Map<String, Object> errors})>
fetchGlobalSubscriptions(AppController ac) async {
  final perAccount = <String, List<DetailedCommunityModel>>{};
  final errors = <String, Object>{};

  await Future.wait([
    for (final account in ac.accounts.keys)
      if (isAccountSignedIn(ac, account))
        () async {
          final api = await ac.getApiForAccount(account);
          if (!api.client.software.canBeAppAccount) return;
          try {
            final all = <DetailedCommunityModel>[];
            String? page;
            for (var i = 0; i < 40; i++) {
              final result = await api.community.list(
                filter: ExploreFilter.subscribed,
                page: page,
              );
              all.addAll(result.items);
              page = result.nextPage;
              if (page == null) break;
            }
            perAccount[account] = all;
          } catch (e) {
            errors[account] = e;
          }
        }(),
  ]);

  // keep the account order stable
  final ordered = {
    for (final a in ac.accounts.keys)
      if (perAccount.containsKey(a)) a: perAccount[a]!,
  };
  final communities = unionByKey<DetailedCommunityModel>(
    ordered,
    (account, c) => communityKey(c.apId, c.name, account.split('@').last),
  );
  return (communities: communities, errors: errors);
}

/// The Combined view's drawer: a global list of subscriptions across all
/// accounts, each showing which accounts follow it.
class GlobalSubscriptionsDrawer extends StatelessWidget {
  const GlobalSubscriptionsDrawer({
    required this.communities,
    required this.loading,
    required this.errors,
    required this.selected,
    required this.onSelect,
    super.key,
  });

  final List<GlobalCommunity> communities;
  final bool loading;
  final Map<String, Object> errors;
  final GlobalCommunity? selected;
  final void Function(GlobalCommunity? community) onSelect;

  @override
  Widget build(BuildContext context) {
    final sorted = [...communities]
      ..sort(
        (a, b) =>
            a.first.title.toLowerCase().compareTo(b.first.title.toLowerCase()),
      );
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        ListTile(
          leading: const Icon(Icons.dynamic_feed),
          title: const Text('All accounts'),
          selected: selected == null,
          onTap: () => onSelect(null),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            'Subscriptions (${communities.length})',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        if (loading) const LinearProgressIndicator(),
        for (final entry in errors.entries)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Text(
              '${entry.key}: ${entry.value}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        for (final community in sorted)
          ListTile(
            leading: Avatar(community.first.icon, radius: 16),
            title: Text(community.first.title, maxLines: 1),
            subtitle: Text(community.key, maxLines: 1),
            trailing: Wrap(
              spacing: 2,
              children: [
                for (final account in community.byAccount.keys)
                  AccountAvatar(account, radius: 8),
              ],
            ),
            selected: selected?.key == community.key,
            onTap: () => onSelect(community),
          ),
      ],
    );
  }
}
