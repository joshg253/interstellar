import 'dart:async';

import 'package:auto_route/annotations.dart';
import 'package:flutter/material.dart';
import 'package:interstellar/src/controller/controller.dart';
import 'package:interstellar/src/controller/server.dart';
import 'package:interstellar/src/screens/account/messages/messages_screen.dart';
import 'package:interstellar/src/screens/account/notification/notification_badge.dart';
import 'package:interstellar/src/screens/account/notification/notification_screen.dart';
import 'package:interstellar/src/utils/utils.dart';
import 'package:interstellar/src/widgets/account_avatar.dart';
import 'package:interstellar/src/widgets/account_switcher.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

@RoutePage()
class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key, this.placeholder = false});

  // This is so the generated route includes parameters so that a key can be passed.
  final bool placeholder;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  // Unread notifications per account, so the switcher shows where something
  // is waiting without opening each account.
  final Map<String, int> _unread = {};
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refreshUnread();
    _timer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _refreshUnread(),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Accounts whose inbox the regular screens can show.
  List<String> _inboxAccounts(AppController ac) => [
    for (final account in ac.accounts.keys)
      if (isAccountSignedIn(ac, account) &&
          (ac.servers[account.split('@').last]?.software.canBeAppAccount ??
              true))
        account,
  ];

  Future<void> _refreshUnread() async {
    final ac = context.read<AppController>();
    await Future.wait([
      for (final account in _inboxAccounts(ac))
        () async {
          try {
            final api = await ac.getApiForAccount(account);
            _unread[account] = await api.notifications.getCount();
          } catch (_) {
            // leave the last known count
          }
        }(),
    ]);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ac = context.watch<AppController>();
    final accounts = _inboxAccounts(ac);
    final selected = ac.selectedAccount;
    final othersUnread = [
      for (final a in accounts)
        if (a != selected) _unread[a] ?? 0,
    ].fold(0, (sum, n) => sum + n);

    return whenLoggedIn(
          context,
          DefaultTabController(
            length: 2,
            child: Scaffold(
              appBar: AppBar(
                title: Text(l(context).inbox),
                actions: [
                  AccountSwitcher(
                    accounts: accounts,
                    unread: _unread,
                    // switching rebuilds the app's routes and may dispose
                    // this screen
                    onSwitched: () {
                      if (mounted) unawaited(_refreshUnread());
                    },
                  ),
                ],
                bottom: TabBar(
                  tabs: [
                    Tab(
                      text: l(context).notifications,
                      icon: const NotificationBadge(
                        child: Icon(Symbols.notifications_rounded),
                      ),
                    ),
                    Tab(
                      text: l(context).messages,
                      icon: const Icon(Symbols.message_rounded),
                    ),
                  ],
                ),
              ),
              body: TabBarView(
                physics: appTabViewPhysics(context),
                children: const [NotificationsScreen(), MessagesScreen()],
              ),
            ),
          ),
        ) ??
        Center(child: Text(l(context).notLoggedIn));
  }
}
