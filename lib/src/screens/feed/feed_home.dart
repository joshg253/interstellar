import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:interstellar/src/controller/controller.dart';
import 'package:interstellar/src/screens/feed/cross_account_feed_screen.dart';
import 'package:interstellar/src/screens/feed/feed_accounts.dart';
import 'package:interstellar/src/screens/feed/feed_screen.dart';
import 'package:provider/provider.dart';

/// The Feed tab. With exactly the app's selected account ticked it is the
/// original [FeedScreen], unchanged; with several accounts ticked it is the
/// merged view, which overrides only what multiple accounts need.
@RoutePage()
class FeedHomeScreen extends StatefulWidget {
  const FeedHomeScreen({
    super.key,
    this.placeholder = false,
    this.scrollController,
  });

  // This is so the generated route includes parameters so that a key can be
  // passed (same trick as the inbox screen).
  final bool placeholder;

  /// Lets the app shell scroll the feed to the top when its tab is tapped again.
  final ScrollController? scrollController;

  @override
  State<FeedHomeScreen> createState() => _FeedHomeScreenState();
}

class _FeedHomeScreenState extends State<FeedHomeScreen> {
  late final FeedAccounts _accounts;
  String? _selectedSeen;
  bool _switching = false;

  @override
  void initState() {
    super.initState();
    final ac = context.read<AppController>();
    _selectedSeen = ac.selectedAccount;
    _accounts = FeedAccounts({ac.selectedAccount})..addListener(_onAccounts);
  }

  void _onAccounts() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _accounts
      ..removeListener(_onAccounts)
      ..dispose();
    super.dispose();
  }

  bool _selectable(AppController ac, String account) =>
      ac.servers[account.split('@').last]?.software.canBeAppAccount ?? true;

  @override
  Widget build(BuildContext context) {
    final ac = context.watch<AppController>();

    // The selected account changed from elsewhere (e.g. the inbox switcher):
    // the feed follows it, as the original Feed always has, unless it was
    // already ticked, in which case the ticked set is kept.
    if (_selectedSeen != ac.selectedAccount) {
      _selectedSeen = ac.selectedAccount;
      _switching = false;
      if (!_accounts.includes(ac.selectedAccount)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _accounts.set({ac.selectedAccount});
        });
      }
    }

    final single = _accounts.single(ac);

    if (single != null && single == ac.selectedAccount) {
      return FeedScreen(
        key: const ValueKey('feed'),
        feedName: 'home',
        scrollController: widget.scrollController,
        accountsAction: FeedAccountsButton(accounts: _accounts),
      );
    }

    // One account ticked that is not the selected one: make it the selected
    // account, so the original Feed runs on it exactly as it would anyway.
    if (single != null && !_switching && _selectable(ac, single)) {
      _switching = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ac.switchAccounts(single);
      });
    }

    return CombinedFeedScreen(
      key: const ValueKey('combined'),
      accounts: _accounts,
      scrollController: widget.scrollController,
    );
  }
}
