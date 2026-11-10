import 'package:flutter/material.dart';
import 'package:interstellar/src/api/api.dart';
import 'package:interstellar/src/api/comments.dart';
import 'package:interstellar/src/controller/controller.dart';
import 'package:interstellar/src/models/comment.dart';
import 'package:interstellar/src/models/post.dart';
import 'package:interstellar/src/screens/feed/merged_comments.dart';
import 'package:interstellar/src/screens/feed/post_comment.dart';
import 'package:interstellar/src/screens/feed/post_item.dart';
import 'package:interstellar/src/screens/feed/post_page.dart';
import 'package:interstellar/src/utils/utils.dart';
import 'package:interstellar/src/widgets/account_avatar.dart';
import 'package:interstellar/src/widgets/account_scope.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

/// One account's view of a post's comments.
class CommentSource {
  CommentSource({
    required this.account,
    required this.api,
    required this.postType,
    required this.postId,
    this.numComments,
  });

  final String account;
  final API api;
  final PostType postType;
  final int postId;

  /// Comment count the account reported for the post, if known.
  final int? numComments;

  List<CommentModel> items = [];

  /// Empty string is the first page; null means exhausted (or failed).
  String? next = '';
  Object? error;
}

/// Comments for one post as seen from several accounts, merged into a single
/// tree. Each comment is shown once, through the account picked in the
/// selector, so votes, replies and the other actions act as that account.
class MergedCommentSection extends StatefulWidget {
  const MergedCommentSection({
    required this.sources,
    required this.sort,
    required this.opUserId,
    this.isLocked = false,
    super.key,
  });

  final List<CommentSource> sources;
  final CommentSort sort;
  final int opUserId;
  final bool isLocked;

  @override
  State<MergedCommentSection> createState() => _MergedCommentSectionState();
}

List<CommentModel> _replaceIn(List<CommentModel> list, CommentModel updated) =>
    list
        .map(
          (c) => c.id == updated.id
              ? updated
              : c.copyWith(
                  children: c.children == null
                      ? null
                      : _replaceIn(c.children!, updated),
                ),
        )
        .toList();

class _MergedCommentSectionState extends State<MergedCommentSection> {
  // Own the mutable copies so a parent rebuild does not reset loaded pages.
  late final List<CommentSource> _sources = [
    for (final s in widget.sources)
      CommentSource(
        account: s.account,
        api: s.api,
        postType: s.postType,
        postId: s.postId,
        numComments: s.numComments,
      ),
  ];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  bool get _hasMore => _sources.any((s) => s.next != null);

  Future<void> _loadMore() async {
    if (_loading) return;
    setState(() => _loading = true);
    await Future.wait(
      _sources.where((s) => s.next != null).map((s) async {
        try {
          final page = await s.api.comments.list(
            s.postType,
            s.postId,
            page: nullIfEmpty(s.next!),
            sort: widget.sort,
          );
          s
            ..items = [...s.items, ...page.items]
            ..next = page.nextPage;
        } catch (e) {
          s
            ..error = e
            ..next = null;
        }
      }),
    );
    if (!mounted) return;
    setState(() => _loading = false);
  }

  void _update(String account, CommentModel updated) {
    final source = _sources.firstWhere((s) => s.account == account);
    setState(() => source.items = _replaceIn(source.items, updated));
  }

  @override
  Widget build(BuildContext context) {
    final ac = context.watch<AppController>();
    final nodes = mergeTrees<CommentModel>(
      [for (final s in _sources) (s.account, s.items)],
      keyOf: (c) => c.apId,
      childrenOf: (c) => c.children ?? const [],
    );
    final apis = {for (final s in _sources) s.account: s.api};
    final failed = _sources.where((s) => s.error != null).toList();

    return ValueListenableBuilder<String?>(
      valueListenable: interactAccount,
      builder: (context, _, _) {
        final active = resolveActiveAccount(ac, [
          for (final s in _sources) s.account,
        ]);
        return SliverMainAxisGroup(
          slivers: [
            if (!_loading && nodes.isEmpty && !_hasMore)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('No comments on any account yet.'),
                ),
              ),
            SliverList.builder(
              itemCount: nodes.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: MergedCommentTile(
                  node: nodes[i],
                  apis: apis,
                  onUpdate: _update,
                  active: active,
                  opUserId: widget.opUserId,
                  postLocked: widget.isLocked,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Column(
                children: [
                  for (final s in failed)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text('${s.account}: ${s.error}'),
                    ),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_hasMore)
                    TextButton(
                      onPressed: _loadMore,
                      child: const Text('Load more comments'),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class MergedCommentTile extends StatelessWidget {
  const MergedCommentTile({
    required this.node,
    required this.apis,
    required this.onUpdate,
    required this.active,
    required this.opUserId,
    required this.postLocked,
    this.level = 0,
    super.key,
  });

  final MergedNode<CommentModel> node;
  final Map<String, API> apis;
  final void Function(String account, CommentModel updated) onUpdate;

  /// The account chosen in the selector; its copy of the comment is shown.
  final String? active;
  final int opUserId;
  final bool postLocked;
  final int level;

  @override
  Widget build(BuildContext context) {
    final (account, comment) = pickCopy(node.copies, active);
    // A score is a server's tally, so list each server once (two accounts on
    // the same server would show the same number). It is formatted like the
    // vote buttons: one net number, or separate up and down counts when the
    // Split votes setting is on (servers with no downvotes show up only).
    final split = context.watch<AppController>().profile.splitVotes;
    final seenHosts = <String>{};
    final scores = [
      for (final c in node.copies)
        if (seenHosts.add(c.$1.split('@').last))
          '${c.$1.split('@').last} ${_score(c.$2, split)}',
    ].join(',  ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AccountScope(
          account: account,
          api: apis[account]!,
          standIn: active != null && account != active,
          child: PostComment(
            comment,
            (updated) => onUpdate(account, updated),
            key: ValueKey((account, comment.id)),
            opUserId: opUserId,
            postLocked: postLocked,
            level: level,
            showChildren: false,
          ),
        ),
        // Right-aligned, where the vote buttons are.
        Padding(
          padding: const EdgeInsets.only(left: 12, right: 12, bottom: 4),
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              [
                if (active != null && account != active) 'via $account',
                scores,
              ].join('  |  '),
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ),
        if (node.children.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(left: 1),
            padding: const EdgeInsets.only(left: 9),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: Colors.primaries[level % Colors.primaries.length],
                  width: 2,
                ),
              ),
            ),
            child: Column(
              children: [
                for (final child in node.children)
                  MergedCommentTile(
                    node: child,
                    apis: apis,
                    onUpdate: onUpdate,
                    active: active,
                    opUserId: opUserId,
                    postLocked: postLocked,
                    level: level + 1,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The account to act as: an explicit pick if it is one of [accounts] and
/// can act; otherwise the account the user is on ([selected]); otherwise the
/// first that can; null if none can.
String? pickActiveAccount({
  required String? chosen,
  required String? selected,
  required List<String> accounts,
  required bool Function(String account) signedIn,
}) {
  for (final candidate in [chosen, selected]) {
    if (candidate != null &&
        accounts.contains(candidate) &&
        signedIn(candidate)) {
      return candidate;
    }
  }
  return accounts.where(signedIn).firstOrNull;
}

/// Whether the account the user picked in "Interact as" has no copy in a group
/// of [accounts]. The group then shows another account's copy, which must be
/// read-only: acting on it would act as an account the user did not pick.
bool chosenAccountMissing(String? chosen, List<String> accounts) =>
    chosen != null && !accounts.contains(chosen);

/// The account to act as in merged views (see [pickActiveAccount]).
String? resolveActiveAccount(AppController ac, List<String> accounts) =>
    pickActiveAccount(
      chosen: interactAccount.value,
      selected: ac.selectedAccount,
      accounts: accounts,
      signedIn: (a) => isAccountSignedIn(ac, a),
    );

/// App bar account picker: shows the account in use and opens a menu to
/// change it. The choice is global and sticky, shared by the list screen and
/// the post page; guests are listed but can't be chosen. [counts] optionally
/// adds each account's comment count to its menu entry.
class AccountMenuButton extends StatelessWidget {
  const AccountMenuButton({
    required this.accounts,
    this.counts = const {},
    this.pending = const [],
    this.onResolve,
    super.key,
  });

  final List<String> accounts;
  final Map<String, int> counts;

  /// Signed-in accounts without a copy; choosing one calls [onResolve] first
  /// and only selects it if that returns true.
  final List<String> pending;
  final Future<bool> Function(String account)? onResolve;

  @override
  Widget build(BuildContext context) {
    final ac = context.watch<AppController>();
    return ValueListenableBuilder<String?>(
      valueListenable: interactAccount,
      builder: (context, _, _) {
        final active = resolveActiveAccount(ac, accounts);
        return PopupMenuButton<String>(
          tooltip: 'Interact as ${active ?? 'none (all guests)'}',
          onSelected: (account) async {
            if (pending.contains(account) &&
                !(await onResolve?.call(account) ?? false)) {
              return;
            }
            interactAccount.value = account;
          },
          itemBuilder: (context) => [
            for (final account in pending)
              PopupMenuItem<String>(
                value: account,
                child: Row(
                  spacing: 8,
                  children: [
                    Opacity(opacity: 0.5, child: AccountAvatar(account)),
                    Flexible(child: Text('$account - tap to look up post')),
                  ],
                ),
              ),
            for (final account in accounts)
              PopupMenuItem<String>(
                value: account,
                enabled: isAccountSignedIn(ac, account),
                child: Row(
                  spacing: 8,
                  children: [
                    AccountAvatar(account),
                    Flexible(
                      child: Text(
                        '$account'
                        '${counts[account] == null ? '' : ' (${counts[account]})'}'
                        '${isAccountSignedIn(ac, account) ? '' : ' - guest'}',
                      ),
                    ),
                    if (account == active) const Icon(Icons.check, size: 18),
                  ],
                ),
              ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 6,
              children: [
                if (active == null)
                  const Icon(Icons.account_circle)
                else
                  AccountAvatar(active),
                Text(active == null ? 'guest' : active.split('@').last),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Identity of a cross-post group in a list: its first copy, plus the number
/// of accounts' copies so the section rebuilds when one is added.
Key crossPostGroupKey(MergedNode<PostModel> group, int copies) {
  final (account, post) = group.copies.first;
  return ValueKey((account, post.apId ?? post.id, copies));
}

/// One cross-post (the same link in another community) across all accounts: a
/// header row (tap opens the post, the menu shows its card) over its comments,
/// merged like the main post's.
class CrossPostSection extends StatefulWidget {
  const CrossPostSection({
    required this.group,
    required this.apis,
    required this.sort,
    super.key,
  });

  final MergedNode<PostModel> group;
  final Map<String, API> apis;
  final CommentSort sort;

  @override
  State<CrossPostSection> createState() => _CrossPostSectionState();
}

class _CrossPostSectionState extends State<CrossPostSection> {
  // Copies changed locally (e.g. voted), keyed by account.
  final Map<String, PostModel> _overrides = {};

  /// [build] inside the scope of [account]'s copy (read-only when [active] has
  /// none, or when the user's pick has no copy in this group).
  Widget _scoped(
    String account,
    String? active,
    Widget Function(BuildContext context) build,
  ) => AccountScope(
    account: account,
    api: widget.apis[account]!,
    standIn:
        (active != null && account != active) ||
        chosenAccountMissing(interactAccount.value, [
          for (final c in widget.group.copies) c.$1,
        ]),
    child: Builder(builder: build),
  );

  /// The cross-post's full card (votes, actions), in a sheet.
  void _showCard(BuildContext context, String account, String? active) {
    final post = widget.group.copies.firstWhere((c) => c.$1 == account).$2;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (_, setSheet) => _scoped(
          account,
          active,
          (innerContext) => SingleChildScrollView(
            child: PostItem(_overrides[account] ?? post, (updated) {
              setState(() => _overrides[account] = updated);
              setSheet(() {});
            }),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ac = context.watch<AppController>();
    final copies = [
      for (final (account, post) in widget.group.copies)
        (account, _overrides[account] ?? post),
    ];
    final first = copies.first.$2;

    return SliverMainAxisGroup(
      slivers: [
        const SliverToBoxAdapter(child: Divider()),
        SliverToBoxAdapter(
          child: ValueListenableBuilder<String?>(
            valueListenable: interactAccount,
            builder: (context, _, _) {
              final active = resolveActiveAccount(ac, [
                for (final c in copies) c.$1,
              ]);
              final (account, post) = pickCopy(copies, active);
              return _scoped(
                account,
                active,
                (innerContext) => ListTile(
                  title: Text(
                    l(innerContext).crossPostComments(post.community.name),
                    style: Theme.of(innerContext).textTheme.titleMedium,
                  ),
                  trailing: IconButton(
                    onPressed: () => _showCard(innerContext, account, active),
                    icon: const Icon(Symbols.more_vert_rounded),
                  ),
                  onTap: () => pushPostPage(
                    innerContext,
                    communityName: post.community.name,
                    initData: post,
                  ),
                ),
              );
            },
          ),
        ),
        MergedCommentSection(
          key: Key('xpost-${first.apId ?? first.id}-${widget.sort}'),
          sort: widget.sort,
          opUserId: first.user.id,
          isLocked: first.isLocked,
          sources: [
            for (final (account, post) in copies)
              CommentSource(
                account: account,
                api: widget.apis[account]!,
                postType: post.type,
                postId: post.id,
                numComments: post.numComments,
              ),
          ],
        ),
      ],
    );
  }
}

/// A comment's score as one server reports it.
String _score(CommentModel c, bool split) {
  final up = intFormat(c.upvotes ?? 0);
  if (!split) return intFormat((c.upvotes ?? 0) - (c.downvotes ?? 0));
  return c.downvotes == null ? '↑$up' : '↑$up ↓${intFormat(c.downvotes!)}';
}
