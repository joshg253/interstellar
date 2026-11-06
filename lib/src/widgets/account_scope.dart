import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:interstellar/src/api/api.dart';
import 'package:interstellar/src/controller/controller.dart';
import 'package:interstellar/src/controller/server.dart';
import 'package:interstellar/src/models/post.dart';
import 'package:provider/provider.dart';

/// Pins a subtree to one account's API instead of the globally selected one.
/// Screens outside any scope behave exactly as before.
class AccountScope extends InheritedWidget {
  const AccountScope({
    required this.account,
    required this.api,
    required super.child,
    super.key,
  });

  final String account;
  final API api;

  static AccountScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AccountScope>();

  @override
  bool updateShouldNotify(AccountScope oldWidget) =>
      account != oldWidget.account || api != oldWidget.api;
}

extension ScopedApi on BuildContext {
  /// The API of the enclosing [AccountScope], else the selected account's.
  API get scopedApi =>
      AccountScope.maybeOf(this)?.api ?? read<AppController>().api;
}

extension ScopedReadStatus on BuildContext {
  /// Marks posts read on the selected account. Inside an [AccountScope] the
  /// write is skipped (read status is keyed by the selected account, so it
  /// would hit the wrong server); the returned posts still carry the flag.
  Future<List<PostModel>> markPostsRead(
    List<PostModel> posts,
    bool markRead,
  ) async {
    final scope = AccountScope.maybeOf(this);
    if (scope != null) {
      // Lemmy and PieFed keep read state on the server, so mark it on the
      // account the post belongs to. Others have no scoped read state yet.
      final ac = read<AppController>();
      final account = ac.accounts[scope.account];
      final signedIn =
          account != null && (account.jwt != null || account.oauth != null);
      final software = scope.api.client.software;
      if (signedIn &&
          (software == ServerSoftware.lemmy ||
              software == ServerSoftware.piefed)) {
        try {
          await scope.api.threads.markAsRead([
            for (final post in posts) post.id,
          ], markRead);
        } catch (_) {
          // read state is best-effort
        }
      }
      return posts.map((post) => post.copyWith(read: markRead)).toList();
    }
    return read<AppController>().markAsRead(posts, markRead);
  }
}

/// One account's copy of a post that other accounts also returned.
typedef AccountCopy = ({String account, API api, PostModel post});

/// The account chosen for voting and replying in merged views. Sticky for the
/// app session; null until the user picks one.
final ValueNotifier<String?> interactAccount = ValueNotifier<String?>(null);

/// A signed-in account that has no copy of a post yet.
typedef PendingAccount = ({String account, API api});
