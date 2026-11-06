import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:interstellar/src/api/bookmark.dart';
import 'package:interstellar/src/api/comments.dart';
import 'package:interstellar/src/api/notifications.dart';
import 'package:interstellar/src/api/resolve.dart';
import 'package:interstellar/src/controller/controller.dart';
import 'package:interstellar/src/controller/router.gr.dart';
import 'package:interstellar/src/controller/server.dart';
import 'package:interstellar/src/models/comment.dart';
import 'package:interstellar/src/models/post.dart';
import 'package:interstellar/src/screens/feed/merged_comment_section.dart';
import 'package:interstellar/src/screens/feed/merged_comments.dart';
import 'package:interstellar/src/screens/feed/post_comment.dart';
import 'package:interstellar/src/screens/feed/post_item.dart';
import 'package:interstellar/src/widgets/account_scope.dart';
import 'package:interstellar/src/utils/ap_urls.dart';
import 'package:interstellar/src/utils/utils.dart';
import 'package:interstellar/src/widgets/ban_dialog.dart';
import 'package:interstellar/src/widgets/content_item/content_item.dart';
import 'package:interstellar/src/widgets/context_menu.dart';
import 'package:interstellar/src/widgets/loading_button.dart';
import 'package:interstellar/src/widgets/loading_template.dart';
import 'package:interstellar/src/widgets/menus/content_menu.dart';
import 'package:interstellar/src/widgets/paging.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

@RoutePage()
class ThreadPage extends StatelessWidget {
  const ThreadPage({
    @PathParam('communityName') this.communityName,
    @PathParam('id') required this.postId,
    super.key,
    this.initData,
    this.onUpdate,
    this.userCanModerate = false,
  });

  final String? communityName;
  final int postId;
  final PostModel? initData;
  final void Function(PostModel)? onUpdate;
  final bool userCanModerate;

  @override
  Widget build(BuildContext context) => PostPage(
    postType: PostType.thread,
    postId: postId,
    initData: initData,
    onUpdate: onUpdate,
    userCanModerate: userCanModerate,
  );
}

@RoutePage()
class MicroblogPage extends StatelessWidget {
  const MicroblogPage({
    @PathParam('communityName') this.communityName,
    @PathParam('id') required this.postId,
    super.key,
    this.initData,
    this.onUpdate,
    this.userCanModerate = false,
  });

  final String? communityName;
  final int postId;
  final PostModel? initData;
  final void Function(PostModel)? onUpdate;
  final bool userCanModerate;

  @override
  Widget build(BuildContext context) => PostPage(
    postType: PostType.microblog,
    postId: postId,
    initData: initData,
    onUpdate: onUpdate,
    userCanModerate: userCanModerate,
  );
}

Future<void> pushPostPage(
  BuildContext context, {
  String? communityName,
  int? postId,
  PostType? postType,
  PostModel? initData,
  void Function(PostModel)? onUpdate,
  bool userCanModerate = false,
}) async {
  final type = postType ?? initData!.type;
  final id = postId ?? initData!.id;

  // Inside an AccountScope the router would rebuild the page under the
  // selected account, so push a plain route that keeps the scope.
  final scope = AccountScope.maybeOf(context);
  if (scope != null) {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AccountScope(
          account: scope.account,
          api: scope.api,
          child: PostPage(
            postType: type,
            postId: id,
            initData: initData,
            onUpdate: onUpdate,
            userCanModerate: userCanModerate,
          ),
        ),
      ),
    );
    return;
  }

  context.router.push(
    type == PostType.thread
        ? ThreadRoute(
            communityName: communityName,
            postId: id,
            initData: initData,
            userCanModerate: userCanModerate,
            onUpdate: onUpdate,
          )
        : MicroblogRoute(
            communityName: communityName,
            postId: id,
            initData: initData,
            userCanModerate: userCanModerate,
            onUpdate: onUpdate,
          ),
  );
}

// @RoutePage()
class PostPage extends StatefulWidget {
  const PostPage({
    this.postType,
    @PathParam('id') this.postId,
    this.initData,
    this.onUpdate,
    super.key,
    this.userCanModerate = false,
    this.copies = const [],
    this.candidates = const [],
  });

  final PostType? postType;
  final int? postId;
  final PostModel? initData;
  final void Function(PostModel)? onUpdate;
  final bool userCanModerate;

  /// Other accounts' copies of this post; each gets its own comment section.
  final List<AccountCopy> copies;

  /// Signed-in accounts with no copy yet; picking one resolves the post there.
  final List<PendingAccount> candidates;

  @override
  State<PostPage> createState() => _PostPageState();
}

class _PostPageState extends State<PostPage> {
  PostModel? _data;

  // Latest state of the other accounts' copies of this post.
  late final Map<String, PostModel> _copyPosts = {
    for (final c in widget.copies) c.account: c.post,
  };

  // Copies added by resolving the post on another account.
  final List<AccountCopy> _resolved = [];

  List<AccountCopy> get _copies => [...widget.copies, ..._resolved];

  CommentSort commentSort = CommentSort.hot;

  @override
  void initState() {
    super.initState();

    commentSort = context.read<AppController>().profile.feedDefaultCommentSort;

    _initData();
  }

  Future<void> _initData() async {
    if (widget.initData != null) {
      _data = widget.initData;
    }
    // Cross posts are only returned on fetching single post not on list
    // so need to fetch full post info.
    if (widget.postType != null && widget.postId != null || _data != null) {
      final ac = context.read<AppController>();
      final newPost = await switch (widget.postType ?? _data!.type) {
        PostType.thread => context.scopedApi.threads.get(
          widget.postId ?? _data!.id,
        ),
        PostType.microblog => context.scopedApi.microblogs.get(
          widget.postId ?? _data!.id,
        ),
      };
      if (!mounted) return;
      setState(() {
        _data = newPost;
      });
    } else if (_data == null) {
      throw Exception('Post data was uninitialized');
    }

    unawaited(_loadCopies());

    if (!mounted) return;
    _onUpdate(
      (await context.markPostsRead([
        _data!,
        ...?(context.read<AppController>().profile.markCrossPostsAsRead
            ? _data!.crossPosts
            : null),
      ], true)).first,
    );
  }

  /// The list models of the other accounts' copies have no cross-posts (only
  /// the single-post fetch returns them), so fetch each in full.
  Future<void> _loadCopies() => Future.wait(widget.copies.map(_loadCopy));

  Future<void> _loadCopy(AccountCopy copy) async {
    try {
      final full = await switch (copy.post.type) {
        PostType.thread => copy.api.threads.get(copy.post.id),
        PostType.microblog => copy.api.microblogs.get(copy.post.id),
      };
      if (!mounted) return;
      setState(() => _copyPosts[copy.account] = full);
    } catch (_) {
      // keep the list copy; its cross-posts just won't show
    }
  }

  /// Accounts that have no copy of this post yet, and so can be resolved.
  List<PendingAccount> get _pending => [
    for (final c in widget.candidates)
      if (!_copies.any((copy) => copy.account == c.account)) c,
  ];

  /// Asks [account]'s server to fetch this post, then adds its copy. Returns
  /// whether the account now has one.
  Future<bool> _resolveFor(String account) async {
    final candidate = _pending.firstWhereOrNull((c) => c.account == account);
    final apId = _data?.apId;
    if (candidate == null || apId == null) return false;

    String? problem;
    try {
      final found = await resolvePost(candidate.api.client, apId);
      if (found == null) {
        problem = 'could not find this post';
      } else if (mounted) {
        final copy = (account: account, api: candidate.api, post: found);
        setState(() => _resolved.add(copy));
        unawaited(_loadCopy(copy));
        return true;
      }
    } catch (e) {
      problem = '$e';
    }
    if (mounted && problem != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$account: $problem')));
    }
    return false;
  }

  void _onUpdate(PostModel newValue) {
    if (!mounted) return;
    setState(() {
      _data = newValue;
    });
    widget.onUpdate?.call(newValue);
  }

  void _updateCrossPost(PostModel crossPost) {
    final newCrossPosts = _data!.crossPosts.toList();
    final indexOfPost = newCrossPosts.indexWhere(
      (post) => post.id == crossPost.id,
    );
    newCrossPosts[indexOfPost] = crossPost;
    _onUpdate(_data!.copyWith(crossPosts: newCrossPosts));
  }

  Future<void> showCrossPostMenu(
    BuildContext context,
    PostModel crossPost,
  ) async {
    final ac = context.read<AppController>();
    final canModerate = crossPost.canAuthUserModerate ?? false;
    final contentItem = ContentItem(
      originInstance: getNameHost(context, crossPost.user.name),
      id: crossPost.id,
      user: crossPost.user,
      updateUser: (user) async {
        _updateCrossPost(crossPost.copyWith(user: user));
      },
      community: crossPost.community,
      boosts: crossPost.boosts,
      isBoosted: crossPost.myBoost ?? false,
      onBoost: whenLoggedIn(context, () async {
        _updateCrossPost(
          (await context.markPostsRead([
            await switch (crossPost.type) {
              PostType.thread => context.scopedApi.threads.boost(crossPost.id),
              PostType.microblog => context.scopedApi.microblogs.putVote(
                crossPost.id,
                1,
              ),
            },
          ], true)).first,
        );
      }),
      upVotes: crossPost.upvotes,
      isUpVoted: crossPost.myVote == 1,
      onUpVote: whenLoggedIn(context, () async {
        _updateCrossPost(
          (await context.markPostsRead([
            await switch (crossPost.type) {
              PostType.thread => context.scopedApi.threads.vote(
                crossPost.id,
                1,
                crossPost.myVote == 1 ? 0 : 1,
              ),
              PostType.microblog => context.scopedApi.microblogs.putFavorite(
                crossPost.id,
              ),
            },
          ], true)).first,
        );
      }),
      downVotes: crossPost.downvotes,
      isDownVoted: crossPost.myVote == -1,
      onDownVote: whenLoggedIn(context, () async {
        _updateCrossPost(
          (await context.markPostsRead([
            await switch (crossPost.type) {
              PostType.thread => context.scopedApi.threads.vote(
                crossPost.id,
                -1,
                crossPost.myVote == -1 ? 0 : -1,
              ),
              PostType.microblog => context.scopedApi.microblogs.putVote(
                crossPost.id,
                -1,
              ),
            },
          ], true)).first,
        );
      }),
      contentTypeName: l(context).post,
      onReport: whenLoggedIn(context, (reason) async {
        await switch (crossPost.type) {
          PostType.thread => context.scopedApi.threads.report(
            crossPost.id,
            reason,
          ),
          PostType.microblog => context.scopedApi.microblogs.report(
            crossPost.id,
            reason,
          ),
        };
      }),
      onMarkAsRead: () async {
        _updateCrossPost(
          (await context.markPostsRead([crossPost], !crossPost.read)).first,
        );
      },
      onModeratePin: !canModerate
          ? null
          : () async {
              _updateCrossPost(
                await context.scopedApi.moderation.postPin(
                  crossPost.type,
                  crossPost.id,
                  !crossPost.isPinned,
                ),
              );
            },
      onModerateMarkNSFW: !canModerate
          ? null
          : () async {
              _updateCrossPost(
                await context.scopedApi.moderation.postMarkNSFW(
                  crossPost.type,
                  crossPost.id,
                  !crossPost.isNSFW,
                ),
              );
            },
      onModerateDelete: !canModerate
          ? null
          : () async {
              _updateCrossPost(
                await context.scopedApi.moderation.postDelete(
                  crossPost.type,
                  crossPost.id,
                  true,
                ),
              );
            },
      onModerateBan: !canModerate
          ? null
          : () async {
              await openBanDialog(
                context,
                user: crossPost.user,
                community: crossPost.community,
              );
            },
      onModerateLock: !canModerate
          ? null
          : () async {
              _updateCrossPost(
                await context.scopedApi.moderation.postLock(
                  crossPost.type,
                  crossPost.id,
                  !crossPost.isLocked,
                ),
              );
            },
      numComments: crossPost.numComments,
      editDraftResourceId:
          'edit:${crossPost.type.name}:${ac.instanceHost}:${crossPost.id}',
      replyDraftResourceId:
          'reply:${crossPost.type.name}:${ac.instanceHost}:${crossPost.id}',
      activeBookmarkLists: crossPost.bookmarks,
      loadPossibleBookmarkLists: whenLoggedIn(
        context,
        () async => (await context.scopedApi.bookmark.getBookmarkLists())
            .map((list) => list.name)
            .toList(),
        matchesSoftware: ServerSoftware.mbin,
      ),
      onAddBookmark: whenLoggedIn(context, () async {
        try {
          final newBookmarks = await context.scopedApi.bookmark
              .addBookmarkToDefault(
                subjectType: BookmarkListSubject.fromPostType(
                  postType: crossPost.type,
                  isComment: false,
                ),
                subjectId: crossPost.id,
              );
          _updateCrossPost(crossPost.copyWith(bookmarks: newBookmarks));
        } catch (e) {
          //
        }
      }),
      onAddBookmarkToList: whenLoggedIn(context, (String listName) async {
        final newBookmarks = await context.scopedApi.bookmark.addBookmarkToList(
          subjectType: BookmarkListSubject.fromPostType(
            postType: crossPost.type,
            isComment: false,
          ),
          subjectId: crossPost.id,
          listName: listName,
        );
        _updateCrossPost(crossPost.copyWith(bookmarks: newBookmarks));
      }, matchesSoftware: ServerSoftware.mbin),
      onRemoveBookmark: whenLoggedIn(context, () async {
        try {
          final newBookmarks = await context.scopedApi.bookmark
              .removeBookmarkFromAll(
                subjectType: BookmarkListSubject.fromPostType(
                  postType: crossPost.type,
                  isComment: false,
                ),
                subjectId: crossPost.id,
              );
          _updateCrossPost(crossPost.copyWith(bookmarks: newBookmarks));
        } catch (e) {
          //
        }
      }),
      onRemoveBookmarkFromList: whenLoggedIn(context, (String listName) async {
        final newBookmarks = await context.scopedApi.bookmark
            .removeBookmarkFromList(
              subjectType: BookmarkListSubject.fromPostType(
                postType: crossPost.type,
                isComment: false,
              ),
              subjectId: crossPost.id,
              listName: listName,
            );
        _updateCrossPost(crossPost.copyWith(bookmarks: newBookmarks));
      }, matchesSoftware: ServerSoftware.mbin),
      notificationControlStatus: crossPost.notificationControlStatus,
      onNotificationControlStatusChange:
          crossPost.notificationControlStatus == null
          ? null
          : (newStatus) async {
              await context.scopedApi.notifications.updateControl(
                targetType: switch (crossPost.type) {
                  PostType.thread => NotificationControlUpdateTargetType.entry,
                  PostType.microblog =>
                    NotificationControlUpdateTargetType.post,
                },
                targetId: crossPost.id,
                status: newStatus,
              );

              _updateCrossPost(
                crossPost.copyWith(notificationControlStatus: newStatus),
              );
            },
      crossPost: crossPost,
      shareLinks: genPostUrls(context, crossPost),
      emojiReactions: crossPost.emojiReactions,
      onEmojiReact: crossPost.emojiReactions == null
          ? null
          : whenLoggedIn(context, (emoji) async {
              _updateCrossPost(
                (await context.markPostsRead([
                  await switch (crossPost.type) {
                    PostType.thread => context.scopedApi.threads.vote(
                      crossPost.id,
                      1,
                      1,
                      emoji: emoji,
                    ),
                    PostType.microblog => throw UnreachableError(),
                  },
                ], true)).first,
              );
            }),
    );
    showContentMenu(context, contentItem);
  }

  Widget _buildPostItem(
    BuildContext context,
    PostModel post,
    void Function(PostModel) onUpdate,
  ) {
    return PostItem(
      post,
      onUpdate,
      onReply: whenLoggedIn(context, (
        body,
        lang, {
        XFile? image,
        String? alt,
      }) async {
        final newComment = await context.scopedApi.comments.create(
          post.type,
          post.id,
          body,
          lang: lang,
          image: image,
          alt: alt,
        );

        _mainCommentSectionKey.currentState?._pagingController.prependPage('', [
          newComment,
        ]);
      }),
      onEdit: post.visibility != PostVisibility.soft_deleted
          ? whenLoggedIn(context, (body) async {
              final newPost = await switch (post.type) {
                PostType.thread => context.scopedApi.threads.edit(
                  post.id,
                  post.title!,
                  post.isOC,
                  body,
                  post.lang,
                  post.isNSFW,
                ),
                PostType.microblog => context.scopedApi.microblogs.edit(
                  post.id,
                  body,
                  post.lang!,
                  post.isNSFW,
                ),
              };
              onUpdate(newPost);
            }, matchesUsername: post.user.name)
          : null,
      onDelete: post.visibility != PostVisibility.soft_deleted
          ? whenLoggedIn(context, () async {
              await switch (post.type) {
                PostType.thread => context.scopedApi.threads.delete(post.id),
                PostType.microblog => context.scopedApi.microblogs.delete(
                  post.id,
                ),
              };

              if (!context.mounted) return;

              onUpdate(
                post.copyWith(
                  body: '_${l(context).postDeleted}_',
                  upvotes: null,
                  downvotes: null,
                  boosts: null,
                  visibility: PostVisibility.soft_deleted,
                ),
              );
            }, matchesUsername: post.user.name)
          : null,
      userCanModerate: widget.userCanModerate,
    );
  }

  GlobalKey<_CommentSectionState> _mainCommentSectionKey =
      GlobalKey<_CommentSectionState>();

  @override
  Widget build(BuildContext context) {
    final currentCommentSortOption = commentSortSelect(
      context,
    ).getOption(commentSort);

    if (_data == null) {
      return const LoadingTemplate();
    }

    final post = _data!;

    final ac = context.read<AppController>();

    // Cross-posts from every account, matched by ActivityPub id.
    final pageScope = AccountScope.maybeOf(context);
    final showMerged = pageScope != null;
    final crossGroups = showMerged
        ? mergeTrees<PostModel>(
            [
              (pageScope.account, post.crossPosts),
              for (final c in _copies)
                (c.account, (_copyPosts[c.account] ?? c.post).crossPosts),
            ],
            keyOf: (p) => p.apId,
            childrenOf: (_) => const [],
          )
        : <MergedNode<PostModel>>[];
    final accountApis = {
      if (pageScope != null) pageScope.account: pageScope.api,
      for (final c in _copies) c.account: c.api,
    };

    return Scaffold(
      appBar: AppBar(
        title: ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            post.title ?? post.body ?? '',
            softWrap: false,
            overflow: TextOverflow.fade,
            maxLines: 1,
          ),
          subtitle: Row(
            children: [
              Text(l(context).comments),
              const SizedBox(width: 6),
              Icon(currentCommentSortOption.icon, size: 20),
              const SizedBox(width: 2),
              Text(currentCommentSortOption.title),
            ],
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              onPressed: () async {
                final newSort = await commentSortSelect(
                  context,
                ).askSelection(context, commentSort);

                if (newSort != null && newSort != commentSort) {
                  setState(() {
                    commentSort = newSort;
                    _mainCommentSectionKey = GlobalKey<_CommentSectionState>();
                  });
                }
              },
              icon: const Icon(Symbols.sort_rounded),
            ),
          ),
          // The account selector is always the rightmost action.
          if (AccountScope.maybeOf(context) case final pageScope?)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: AccountMenuButton(
                accounts: [pageScope.account, ..._copies.map((c) => c.account)],
                counts: {
                  pageScope.account: post.numComments,
                  for (final c in _copies)
                    c.account: (_copyPosts[c.account] ?? c.post).numComments,
                },
                pending: [for (final p in _pending) p.account],
                onResolve: _resolveFor,
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => Future.sync(
            () => setState(
              () => _mainCommentSectionKey = GlobalKey<_CommentSectionState>(),
            ),
          ),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: ValueListenableBuilder<String?>(
                  valueListenable: interactAccount,
                  builder: (context, _, _) {
                    // In a scoped page the header follows the "Interact as"
                    // selector, using that account's own copy of the post.
                    final scope = AccountScope.maybeOf(context);
                    final merged = scope != null;
                    final active = merged
                        ? resolveActiveAccount(ac, [
                            scope.account,
                            ..._copies.map((c) => c.account),
                          ])
                        : null;
                    final copy = merged
                        ? _copies.firstWhereOrNull((c) => c.account == active)
                        : null;
                    final headerAccount = copy?.account ?? scope?.account;
                    final headerApi = copy?.api ?? scope?.api;
                    final post = copy == null
                        ? _data!
                        : (_copyPosts[copy.account] ?? copy.post);
                    void onUpdate(PostModel updated) => copy == null
                        ? _onUpdate(updated)
                        : setState(() => _copyPosts[copy.account] = updated);

                    if (headerAccount == null || headerApi == null) {
                      return _buildPostItem(context, post, onUpdate);
                    }
                    return AccountScope(
                      account: headerAccount,
                      api: headerApi,
                      child: Builder(
                        builder: (innerContext) =>
                            _buildPostItem(innerContext, post, onUpdate),
                      ),
                    );
                  },
                ),
              ),
              if (_data != null && _data!.crossPosts.isNotEmpty && !showMerged)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: ElevatedButton(
                      onPressed: () => ContextMenu(
                        title: l(context).crossPosts,
                        items: _data!.crossPosts
                            .map(
                              (crossPost) => ContextMenuItem(
                                title: crossPost.community.name,
                                subtitle: l(
                                  context,
                                ).commentsX(crossPost.numComments),
                                onTap: () async => pushPostPage(
                                  context,
                                  communityName: crossPost.community.name,
                                  initData: crossPost,
                                ),
                              ),
                            )
                            .toList(),
                      ).openMenu(context),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          l(context).crossPostCount(post.crossPosts.length),
                        ),
                      ),
                    ),
                  ),
                ),
              if (AccountScope.maybeOf(context) != null)
                // The same post as seen from several accounts, merged into
                // one comment tree with a vote row per account.
                MergedCommentSection(
                  key: Key('merged-${post.id}$commentSort-${_copies.length}'),
                  sort: commentSort,
                  opUserId: post.user.id,
                  isLocked: post.isLocked,
                  sources: [
                    CommentSource(
                      account: AccountScope.maybeOf(context)!.account,
                      api: AccountScope.maybeOf(context)!.api,
                      postType: post.type,
                      postId: post.id,
                      numComments: post.numComments,
                    ),
                    for (final copy in _copies)
                      CommentSource(
                        account: copy.account,
                        api: copy.api,
                        postType: copy.post.type,
                        postId: copy.post.id,
                        numComments: copy.post.numComments,
                      ),
                  ],
                )
              else
                CommentSection(
                  id: post.id,
                  postType: post.type,
                  sort: commentSort,
                  opUserId: post.user.id,
                  isLocked: post.isLocked,
                  key: _mainCommentSectionKey,
                ),
              if (showMerged &&
                  context.read<AppController>().profile.showCrossPostComments)
                ...crossGroups.map(
                  (group) => CrossPostSection(
                    key: ValueKey(_copies.length),
                    group: group,
                    apis: accountApis,
                    sort: commentSort,
                  ),
                )
              else if (context
                  .read<AppController>()
                  .profile
                  .showCrossPostComments)
                ...post.crossPosts
                    .where((crossPost) => crossPost.numComments > 0)
                    .map(
                      (crossPost) => SliverMainAxisGroup(
                        slivers: [
                          const SliverToBoxAdapter(child: Divider()),
                          SliverToBoxAdapter(
                            child: ListTile(
                              title: Text(
                                l(
                                  context,
                                ).crossPostComments(crossPost.community.name),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              trailing: LoadingIconButton(
                                onPressed: () =>
                                    showCrossPostMenu(context, crossPost),
                                icon: const Icon(Symbols.more_vert_rounded),
                              ),
                              onTap: () => pushPostPage(
                                context,
                                communityName: crossPost.community.name,
                                initData: crossPost,
                              ),
                              onLongPress: () =>
                                  showCrossPostMenu(context, crossPost),
                            ),
                          ),
                          CommentSection(
                            id: crossPost.id,
                            postType: crossPost.type,
                            sort: commentSort,
                            opUserId: crossPost.user.id,
                            isLocked: crossPost.isLocked,
                            key: Key('${crossPost.id}$commentSort'),
                          ),
                        ],
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

class CommentSection extends StatefulWidget {
  const CommentSection({
    required this.id,
    required this.postType,
    required this.sort,
    required this.opUserId,
    super.key,
    this.canModerate = false,
    this.isLocked = false,
  });

  final int id;
  final PostType postType;
  final CommentSort sort;
  final int opUserId;
  final bool canModerate;
  final bool isLocked;

  @override
  State<CommentSection> createState() => _CommentSectionState();
}

class _CommentSectionState extends State<CommentSection> {
  late final _pagingController =
      AdvancedPagingController<String, CommentModel, int>(
        logger: context.read<AppController>().logger,
        firstPageKey: '',
        getItemId: (item) => item.id,
        fetchPage: (pageKey) async {
          final ac = context.read<AppController>();

          final newPage = await context.scopedApi.comments.list(
            widget.postType,
            widget.id,
            page: nullIfEmpty(pageKey),
            sort: widget.sort,
          );

          return (newPage.items, newPage.nextPage);
        },
      );

  @override
  Widget build(BuildContext context) {
    return AdvancedPagedSliverList(
      controller: _pagingController,
      itemBuilder: (context, item, index) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: PostComment(
          item,
          (newValue) => _pagingController.updateItem(item, newValue),
          opUserId: widget.opUserId,
          userCanModerate: widget.canModerate,
          postLocked: widget.isLocked,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pagingController.dispose();
    super.dispose();
  }
}
