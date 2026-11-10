import 'package:auto_route/annotations.dart';
import 'package:flutter/material.dart';
import 'package:interstellar/src/controller/controller.dart';
import 'package:interstellar/src/models/user.dart';
import 'package:interstellar/src/screens/explore/user_screen.dart';
import 'package:interstellar/src/utils/utils.dart';
import 'package:interstellar/src/widgets/account_switcher.dart';
import 'package:interstellar/src/widgets/error_page.dart';
import 'package:oauth2/oauth2.dart';
import 'package:provider/provider.dart';

@RoutePage()
class SelfFeed extends StatefulWidget {
  const SelfFeed({super.key, this.placeholder = false});

  // This is so the generated route includes parameters so that a key can be passed.
  final bool placeholder;

  @override
  State<SelfFeed> createState() => _SelfFeedState();
}

class _SelfFeedState extends State<SelfFeed> {
  DetailedUserModel? _meUser;
  AuthorizationException? _authError;

  @override
  void initState() {
    super.initState();

    final ac = context.read<AppController>();

    if (ac.isLoggedIn) {
      ac.api.users
          .getMe()
          .then((value) {
            if (!mounted) return;

            setState(() {
              _meUser = value;
              _authError = null;
            });
          })
          .catchError((dynamic error) {
            if (error is AuthorizationException) {
              setState(() {
                _authError = error;
              });
            }
          });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ac = context.read<AppController>();

    // Every state of this tab gets the account switcher, so a guest (or an
    // account that failed to load) can still switch to another account.
    Widget withSwitcher(Widget body) => Scaffold(
      appBar: AppBar(
        title: Text(l(context).account),
        actions: const [AccountSwitcher()],
      ),
      body: body,
    );

    if (!ac.isLoggedIn) {
      return withSwitcher(Center(child: Text(l(context).notLoggedIn)));
    }

    if (_authError != null) {
      return withSwitcher(OAuthErrorPage(error: _authError!));
    }

    if (_meUser == null) {
      return withSwitcher(const Center(child: CircularProgressIndicator()));
    }

    final user = _meUser!;

    return UserScreen(
      username: user.name,
      userId: user.id,
      initData: _meUser,
      accountsAction: const AccountSwitcher(),
    );
  }
}
