import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:interstellar/src/controller/controller.dart';
import 'package:interstellar/src/screens/feed/cross_account_feed_screen.dart';
import 'package:interstellar/src/screens/feed/feed_accounts.dart';
import 'package:interstellar/src/widgets/account_scope.dart'
    show interactAccount;
import 'package:provider/provider.dart';

/// The Feed tab: always the merged view, whether one account or several are
/// ticked. Sources and accounts are both chosen in its filter sheet.
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

  /// The account switcher picks one account: the feed shows just that one,
  /// and you act as it (an earlier "interact as" pick is dropped).
  void _showOnlySelected() {
    if (!mounted) return;
    interactAccount.value = null;
    _accounts.set({context.read<AppController>().selectedAccount});
  }

  @override
  Widget build(BuildContext context) {
    final ac = context.watch<AppController>();

    // The selected account changed from elsewhere (e.g. the inbox switcher):
    // the feed follows it, unless it was already ticked, in which case the
    // ticked set is kept.
    if (_selectedSeen != ac.selectedAccount) {
      _selectedSeen = ac.selectedAccount;
      if (!_accounts.includes(ac.selectedAccount)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _accounts.set({ac.selectedAccount});
        });
      }
    }

    return CombinedFeedScreen(
      key: const ValueKey('combined'),
      accounts: _accounts,
      scrollController: widget.scrollController,
      onSwitched: _showOnlySelected,
    );
  }
}
