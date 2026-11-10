import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:interstellar/src/controller/controller.dart';
import 'package:interstellar/src/widgets/account_avatar.dart';
import 'package:provider/provider.dart';

/// Which of the user's accounts the Feed tab draws from. Shared by the Feed
/// host, the original Feed and the merged view, so ticking accounts in one
/// place is seen by all of them.
class FeedAccounts extends ChangeNotifier {
  FeedAccounts(Set<String> initial) : _included = {...initial};

  Set<String> _included;

  Set<String> get included => _included;

  bool includes(String account) => _included.contains(account);

  void set(Set<String> next) {
    if (setEquals(next, _included)) return;
    _included = {...next};
    notifyListeners();
  }

  /// The only ticked account that still exists, or null if there are none or
  /// several.
  String? single(AppController ac) {
    final live = ac.accounts.keys.where(_included.contains).toList();
    return live.length == 1 ? live.single : null;
  }
}

/// Opens a sheet to tick accounts, with a select-all box beside the label.
/// The choice is applied when the sheet closes.
Future<void> showAccountsSheet(
  BuildContext context,
  FeedAccounts accounts,
) async {
  final ac = context.read<AppController>();
  final all = ac.accounts.keys.toList();
  final included = {...accounts.included};

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheet) {
        final ticked = all.where(included.contains).length;
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Accounts',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  Checkbox(
                    tristate: true,
                    value: ticked == all.length
                        ? true
                        : (ticked == 0 ? false : null),
                    onChanged: (_) => setSheet(() {
                      if (ticked == all.length) {
                        included.clear();
                      } else {
                        included.addAll(all);
                      }
                    }),
                  ),
                ],
              ),
              for (final account in all)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: AccountAvatar(account),
                  title: Text(account),
                  value: included.contains(account),
                  onChanged: (v) => setSheet(() {
                    if (v ?? false) {
                      included.add(account);
                    } else {
                      included.remove(account);
                    }
                  }),
                ),
            ],
          ),
        );
      },
    ),
  );

  accounts.set(included);
}

/// The Feed's account button: the account in use, which opens the sheet.
class FeedAccountsButton extends StatelessWidget {
  const FeedAccountsButton({required this.accounts, super.key});

  final FeedAccounts accounts;

  @override
  Widget build(BuildContext context) {
    final ac = context.watch<AppController>();
    final account = ac.selectedAccount;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => showAccountsSheet(context, accounts),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [AccountAvatar(account), Text(account.split('@').last)],
          ),
        ),
      ),
    );
  }
}
