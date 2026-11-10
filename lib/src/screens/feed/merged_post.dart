import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:interstellar/src/api/comments.dart';
import 'package:interstellar/src/api/resolve.dart';
import 'package:interstellar/src/controller/controller.dart';
import 'package:interstellar/src/models/post.dart';
import 'package:interstellar/src/screens/feed/merged_comment_section.dart';
import 'package:interstellar/src/screens/feed/merged_comments.dart';
import 'package:interstellar/src/widgets/account_scope.dart';
import 'package:provider/provider.dart';

/// The other accounts' copies of one post, as shown on a post page inside an
/// [AccountScope]: their latest state, and the accounts still to be resolved.
class PostCopies extends ChangeNotifier {
  PostCopies({this.copies = const [], this.candidates = const []})
    : _posts = {for (final c in copies) c.account: c.post};

  /// Copies handed in by the feed.
  final List<AccountCopy> copies;

  /// Signed-in accounts with no copy yet; picking one resolves the post there.
  final List<PendingAccount> candidates;

  final Map<String, PostModel> _posts;

  // Copies added by resolving the post on another account.
  final List<AccountCopy> _resolved = [];

  bool _disposed = false;

  List<AccountCopy> get all => [...copies, ..._resolved];

  /// Latest state of [copy]'s post.
  PostModel postOf(AccountCopy copy) => _posts[copy.account] ?? copy.post;

  void update(String account, PostModel post) {
    _posts[account] = post;
    _notify();
  }

  /// Accounts that have no copy of this post yet, and so can be resolved.
  List<PendingAccount> get pending => [
    for (final c in candidates)
      if (!all.any((copy) => copy.account == c.account)) c,
  ];

  /// The list models of the copies have no cross-posts (only the single-post
  /// fetch returns them), so fetch each in full.
  Future<void> loadAll() => Future.wait(copies.map(_load));

  Future<void> _load(AccountCopy copy) async {
    try {
      final full = await switch (copy.post.type) {
        PostType.thread => copy.api.threads.get(copy.post.id),
        PostType.microblog => copy.api.microblogs.get(copy.post.id),
      };
      if (_disposed) return;
      _posts[copy.account] = full;
      _notify();
    } catch (_) {
      // keep the list copy; its cross-posts just won't show
    }
  }

  /// Asks [account]'s server to fetch the post with [apId], then adds its
  /// copy. Returns null on success, else what went wrong.
  Future<String?> resolveFor(String account, String? apId) async {
    final candidate = pending.firstWhereOrNull((c) => c.account == account);
    if (candidate == null || apId == null) return 'could not find this post';

    try {
      final found = await resolvePost(candidate.api.client, apId);
      if (found == null) return 'could not find this post';
      if (_disposed) return null;
      final copy = (account: account, api: candidate.api, post: found);
      _resolved.add(copy);
      _notify();
      unawaited(_load(copy));
      return null;
    } catch (e) {
      return '$e';
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// The account selector of a scoped post page.
Widget mergedAccountMenu(
  BuildContext context,
  PostCopies copies,
  PostModel post,
) {
  final scope = AccountScope.maybeOf(context)!;
  return Padding(
    padding: const EdgeInsets.only(right: 4),
    child: AccountMenuButton(
      accounts: [scope.account, ...copies.all.map((c) => c.account)],
      counts: {
        scope.account: post.numComments,
        for (final c in copies.all) c.account: copies.postOf(c).numComments,
      },
      pending: [for (final p in copies.pending) p.account],
      onResolve: (account) async {
        final problem = await copies.resolveFor(account, post.apId);
        if (problem != null && context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('$account: $problem')));
        }
        return problem == null;
      },
    ),
  );
}

/// The post card of a scoped page. It follows the "Interact as" selector, using
/// that account's own copy of the post.
class MergedPostHeader extends StatelessWidget {
  const MergedPostHeader({
    required this.copies,
    required this.post,
    required this.onUpdate,
    required this.builder,
    super.key,
  });

  final PostCopies copies;

  /// The page account's own post.
  final PostModel post;
  final void Function(PostModel) onUpdate;
  final Widget Function(
    BuildContext context,
    PostModel post,
    void Function(PostModel) onUpdate,
  )
  builder;

  @override
  Widget build(BuildContext context) {
    final ac = context.read<AppController>();
    return ValueListenableBuilder<String?>(
      valueListenable: interactAccount,
      builder: (context, _, _) {
        final scope = AccountScope.maybeOf(context)!;
        final active = resolveActiveAccount(ac, [
          scope.account,
          ...copies.all.map((c) => c.account),
        ]);
        final copy = copies.all.firstWhereOrNull((c) => c.account == active);
        final shown = copy == null ? post : copies.postOf(copy);
        void update(PostModel updated) => copy == null
            ? onUpdate(updated)
            : copies.update(copy.account, updated);

        return AccountScope(
          account: copy?.account ?? scope.account,
          api: copy?.api ?? scope.api,
          child: Builder(
            builder: (innerContext) => builder(innerContext, shown, update),
          ),
        );
      },
    );
  }
}

/// The merged comment tree of a scoped page, then one merged section per
/// cross-posted community.
List<Widget> mergedCommentSlivers(
  BuildContext context,
  PostCopies copies,
  PostModel post,
  CommentSort sort,
) {
  final scope = AccountScope.maybeOf(context)!;
  final all = copies.all;

  final crossGroups = mergeTrees<PostModel>(
    [
      (scope.account, post.crossPosts),
      for (final c in all) (c.account, copies.postOf(c).crossPosts),
    ],
    keyOf: (p) => p.apId,
    childrenOf: (_) => const [],
  );
  final apis = {
    scope.account: scope.api,
    for (final c in all) c.account: c.api,
  };

  return [
    // The same post as seen from several accounts, merged into one comment
    // tree with a vote row per account.
    MergedCommentSection(
      key: Key('merged-${post.id}$sort-${all.length}'),
      sort: sort,
      opUserId: post.user.id,
      isLocked: post.isLocked,
      sources: [
        CommentSource(
          account: scope.account,
          api: scope.api,
          postType: post.type,
          postId: post.id,
          numComments: post.numComments,
        ),
        for (final copy in all)
          CommentSource(
            account: copy.account,
            api: copy.api,
            postType: copy.post.type,
            postId: copy.post.id,
            numComments: copy.post.numComments,
          ),
      ],
    ),
    if (context.read<AppController>().profile.showCrossPostComments)
      for (final group in crossGroups)
        CrossPostSection(
          key: crossPostGroupKey(group, all.length),
          group: group,
          apis: apis,
          sort: sort,
        ),
  ];
}
