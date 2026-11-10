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
    this.standIn = false,
    super.key,
  });

  final String account;
  final API api;

  /// This account's copy is shown because the chosen account has none, so it
  /// is read-only: actions would run as the wrong account.
  final bool standIn;

  static AccountScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AccountScope>();

  @override
  bool updateShouldNotify(AccountScope oldWidget) =>
      account != oldWidget.account ||
      api != oldWidget.api ||
      standIn != oldWidget.standIn;
}

/// Where to open a community or user shown through an [AccountScope]. The
/// screens look targets up on the selected account's server, where the shown
/// account's numeric id means something else (or nothing): from another
/// server the id is dropped and the name made explicit.
({String name, int? id}) scopedTarget(
  String name,
  int id, {
  required String? scopeHost,
  required String viewerHost,
}) {
  if (scopeHost == null || scopeHost == viewerHost) return (name: name, id: id);
  final parts = name.split('@');
  final host = parts.length > 1 ? parts[1] : scopeHost;
  return (
    name: host == viewerHost ? parts.first : '${parts.first}@$host',
    id: null,
  );
}

extension ScopedApi on BuildContext {
  /// The API of the enclosing [AccountScope], else the selected account's.
  API get scopedApi =>
      AccountScope.maybeOf(this)?.api ?? read<AppController>().api;
}

/// The software to branch on: the scoped account's when there is one, else the
/// selected account's.
ServerSoftware scopedSoftware(
  ServerSoftware? scoped,
  ServerSoftware selected,
) => scoped ?? selected;

extension ScopedSoftware on BuildContext {
  /// [scopedSoftware] for the enclosing scope and the selected account.
  ServerSoftware get software => scopedSoftware(
    AccountScope.maybeOf(this)?.api.client.software,
    read<AppController>().serverSoftware,
  );
}

extension ScopedTarget on BuildContext {
  /// [scopedTarget] for the enclosing scope and the selected account.
  ({String name, int? id}) targetFor(String name, int id) {
    return scopedTarget(
      name,
      id,
      scopeHost: AccountScope.maybeOf(this)?.account.split('@').last,
      viewerHost: read<AppController>().instanceHost,
    );
  }
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
