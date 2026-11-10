import 'package:flutter/material.dart';
import 'package:interstellar/src/controller/controller.dart';
import 'package:interstellar/src/models/image.dart';
import 'package:provider/provider.dart';

/// Whether [account] has credentials (as opposed to being a guest).
bool isAccountSignedIn(AppController ac, String account) {
  final a = ac.accounts[account];
  return a != null && (a.jwt != null || a.oauth != null);
}

/// Avatars of the user's own accounts, fetched once per account and shared by
/// every view. Guests have none.
class AccountAvatars {
  static final Map<String, ImageModel?> _cache = {};
  static final Set<String> _requested = {};
  static final ValueNotifier<int> changes = ValueNotifier(0);

  static ImageModel? of(String account) => _cache[account];

  static Future<void> ensure(AppController ac, String account) async {
    if (!_requested.add(account)) return;
    if (!isAccountSignedIn(ac, account)) return;
    try {
      final me = await (await ac.getApiForAccount(account)).users.getMe();
      _cache[account] = me.avatar;
      changes.value++;
    } catch (_) {
      // keep the fallback; allow a retry on the next request
      _requested.remove(account);
    }
  }
}

/// A small avatar for one of the user's accounts: their picture when signed
/// in, otherwise the first letter of the server.
class AccountAvatar extends StatefulWidget {
  const AccountAvatar(this.account, {this.radius = 12, super.key});

  final String account;
  final double radius;

  @override
  State<AccountAvatar> createState() => _AccountAvatarState();
}

class _AccountAvatarState extends State<AccountAvatar> {
  @override
  void initState() {
    super.initState();
    AccountAvatars.ensure(context.read<AppController>(), widget.account);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AccountAvatars.changes,
      builder: (context, _, _) {
        final image = AccountAvatars.of(widget.account);
        final host = widget.account.split('@').last;
        final letter = CircleAvatar(
          radius: widget.radius,
          child: Text(
            host.isEmpty ? '?' : host[0].toUpperCase(),
            style: TextStyle(fontSize: widget.radius),
          ),
        );
        return Tooltip(
          message: widget.account,
          child: image == null
              ? letter
              : ClipOval(
                  child: SizedBox(
                    width: widget.radius * 2,
                    height: widget.radius * 2,
                    child: Image.network(
                      image.src,
                      fit: BoxFit.cover,
                      // On web, fall back to the browser's own image loading
                      // when the server doesn't allow cross-origin pixels.
                      webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                      errorBuilder: (_, _, _) => letter,
                    ),
                  ),
                ),
        );
      },
    );
  }
}
