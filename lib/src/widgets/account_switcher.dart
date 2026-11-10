import 'package:flutter/material.dart';
import 'package:interstellar/src/controller/controller.dart';
import 'package:interstellar/src/utils/utils.dart';
import 'package:interstellar/src/widgets/account_avatar.dart';
import 'package:provider/provider.dart';

/// The rightmost top-bar button on screens that belong to one account (Inbox,
/// Account): the account in use, as avatar and host, whose menu switches the
/// app's selected account. A badge shows unread notifications of the other
/// accounts when [unread] is given.
class AccountSwitcher extends StatelessWidget {
  const AccountSwitcher({
    this.accounts,
    this.unread = const {},
    this.onSwitched,
    super.key,
  });

  /// Accounts offered; defaults to every account the app can select (all but
  /// Mastodon, which cannot be the selected account yet).
  final List<String>? accounts;

  /// Unread notification count per account.
  final Map<String, int> unread;

  /// Called after the switch has completed.
  final VoidCallback? onSwitched;

  @override
  Widget build(BuildContext context) {
    final ac = context.watch<AppController>();
    final selected = ac.selectedAccount;
    final offered =
        accounts ??
        [
          for (final account in ac.accounts.keys)
            if (ac.servers[account.split('@').last]?.software.canBeAppAccount ??
                true)
              account,
        ];
    final othersUnread = [
      for (final a in offered)
        if (a != selected) unread[a] ?? 0,
    ].fold(0, (sum, n) => sum + n);

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: PopupMenuButton<String>(
        tooltip: 'Switch account',
        onSelected: (account) async {
          await ac.switchAccounts(account);
          onSwitched?.call();
        },
        itemBuilder: (context) => [
          for (final account in offered)
            PopupMenuItem<String>(
              value: account,
              child: Row(
                spacing: 8,
                children: [
                  AccountAvatar(account),
                  Flexible(child: Text(account)),
                  if ((unread[account] ?? 0) > 0)
                    Badge(label: Text(intFormat(unread[account]!))),
                  if (account == selected) const Icon(Icons.check, size: 18),
                ],
              ),
            ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Badge(
            isLabelVisible: othersUnread > 0,
            label: Text(intFormat(othersUnread)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 6,
              children: [
                AccountAvatar(selected),
                Text(selected.split('@').last),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
