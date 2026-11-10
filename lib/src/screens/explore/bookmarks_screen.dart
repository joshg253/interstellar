import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:interstellar/src/controller/controller.dart';
import 'package:interstellar/src/controller/router.gr.dart';
import 'package:interstellar/src/controller/server.dart';
import 'package:interstellar/src/models/bookmark_list.dart';
import 'package:interstellar/src/models/comment.dart';
import 'package:interstellar/src/models/post.dart';
import 'package:interstellar/src/screens/explore/bookmark_filter.dart';
import 'package:interstellar/src/screens/feed/post_comment.dart';
import 'package:interstellar/src/screens/feed/post_item.dart';
import 'package:interstellar/src/screens/feed/post_page.dart';
import 'package:interstellar/src/utils/utils.dart';
import 'package:interstellar/src/widgets/loading_button.dart';
import 'package:interstellar/src/widgets/paging.dart';
import 'package:interstellar/src/widgets/text_editor.dart';
import 'package:provider/provider.dart';

@RoutePage()
class BookmarkListScreen extends StatefulWidget {
  const BookmarkListScreen({super.key});

  @override
  State<BookmarkListScreen> createState() => _BookmarkListScreenState();
}

class _BookmarkListScreenState extends State<BookmarkListScreen> {
  List<BookmarkListModel> _bookmarkLists = [];
  final _newListController = TextEditingController();

  @override
  void initState() {
    super.initState();

    _fetch();
  }

  Future<void> _fetch() async {
    final ac = context.read<AppController>();

    final lists = await ac.api.bookmark.getBookmarkLists();
    setState(() {
      _bookmarkLists = lists;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ac = context.read<AppController>();

    return Scaffold(
      appBar: AppBar(title: Text(l(context).bookmarkLists)),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: TextEditor(
                        _newListController,
                        hint: l(context).bookmarkLists_createHint,
                      ),
                    ),
                  ),
                  LoadingFilledButton(
                    onPressed: () async {
                      if (_newListController.text.isEmpty) return;
                      await ac.api.bookmark.createBookmarkList(
                        _newListController.text,
                      );
                      _fetch();
                    },
                    label: Text(l(context).bookmarkLists_create),
                  ),
                ],
              ),
            ),
          ),
          SliverList.builder(
            itemCount: _bookmarkLists.length,
            itemBuilder: (context, index) {
              return ListTile(
                title: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_bookmarkLists[index].name),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (!_bookmarkLists[index].isDefault)
                          LoadingFilledButton(
                            onPressed: () async {
                              await ac.api.bookmark.makeBookmarkListDefault(
                                _bookmarkLists[index].name,
                              );
                              _fetch();
                            },
                            label: Text(l(context).bookmarkLists_setDefault),
                          ),
                        if (!_bookmarkLists[index].isDefault)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: LoadingFilledButton(
                              onPressed: () => showDialog<void>(
                                context: context,
                                builder: (BuildContext context) => AlertDialog(
                                  title: const Text('Delete bookmark list'),
                                  content: Text(_bookmarkLists[index].name),
                                  actions: [
                                    OutlinedButton(
                                      onPressed: () => context.router.pop(),
                                      child: Text(l(context).cancel),
                                    ),
                                    FilledButton(
                                      onPressed: () async {
                                        await ac.api.bookmark
                                            .deleteBookmarkList(
                                              _bookmarkLists[index].name,
                                            );
                                        _fetch();
                                        if (!context.mounted) return;
                                        context.router.pop();
                                      },
                                      child: Text(l(context).delete),
                                    ),
                                  ],
                                ),
                              ),
                              label: Text(l(context).delete),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                trailing: Text(_bookmarkLists[index].count.toString()),
                onTap: () => context.router.push(
                  BookmarksRoute(bookmarkList: _bookmarkLists[index].name),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

@RoutePage()
class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({
    super.key,
    @PathParam('bookmarkList') this.bookmarkList,
  });

  final String? bookmarkList;

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  var _sort = BookmarkSort.newest;
  var _filter = const BookmarkFilter();
  final _searchController = TextEditingController();

  late final _pagingController =
      AdvancedPagingController<String, dynamic, String>(
        logger: context.read<AppController>().logger,
        firstPageKey: '',
        // Posts and comments are numbered separately, so an id alone can collide.
        getItemId: (item) => '${item.runtimeType}:${item.id}',
        fetchPage: (pageKey) async {
          final ac = context.read<AppController>();

          final bookmarks = await ac.api.bookmark.list(
            page: nullIfEmpty(pageKey),
            list: widget.bookmarkList,
            sort: _sort.mbinValue,
            // Looked up below, and only for what the filter shows.
            ownVotes: false,
          );

          return (bookmarks.$1, bookmarks.$2);
        },
      );

  /// Ids of items whose own vote is already fetched or being fetched.
  final _voted = <String>{};

  bool get _isMbin =>
      context.read<AppController>().serverSoftware == ServerSoftware.mbin;

  @override
  void initState() {
    super.initState();
    _pagingController.addListener(_syncVotes);
  }

  String _key(dynamic item) => '${item.runtimeType}:${item.id}';

  /// Mbin leaves your vote out of a bookmark list, and looking one up marks
  /// notifications read, so only items that are shown get that lookup.
  Future<void> _syncVotes() async {
    final pages = _pagingController.value.pages;
    if (pages == null) {
      _voted.clear();
      return;
    }
    if (!_isMbin) return;
    final todo = [
      for (final dynamic item in pages.expand((p) => p))
        if (_filter.matches(item as Object) && _voted.add(_key(item))) item,
    ];
    final api = context.read<AppController>().api.bookmark;
    for (var i = 0; i < todo.length; i += 5) {
      final batch = todo.skip(i).take(5).toList();
      final fresh = await Future.wait(batch.map(api.withOwnVote));
      if (!mounted) return;
      for (var j = 0; j < batch.length; j++) {
        if (!identical(batch[j], fresh[j])) {
          _pagingController.updateItem(batch[j], fresh[j]);
        }
      }
    }
  }

  int _matches() =>
      _pagingController.value.pages
          ?.expand((p) => p)
          .where((i) => _filter.matches(i as Object))
          .length ??
      0;

  void _setFilter(BookmarkFilter filter) {
    setState(() => _filter = filter);
    unawaited(_syncVotes());
  }

  void _setSort(BookmarkSort sort) {
    if (sort == _sort) return;
    setState(() => _sort = sort);
    _pagingController.refresh();
  }

  String _sortLabel(BookmarkSort sort) => switch (sort) {
    BookmarkSort.newest => l(context).sort_newest,
    BookmarkSort.oldest => l(context).sort_oldest,
    BookmarkSort.top => l(context).sort_top,
    BookmarkSort.hot => l(context).sort_hot,
  };

  Widget _filterBar() {
    final text = l(context);
    final kinds = {
      BookmarkKind.all: text.filter_all,
      BookmarkKind.threads: text.threads,
      BookmarkKind.posts: text.bookmarks_posts,
      BookmarkKind.comments: text.comments,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: text.bookmarks_search,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _filter.query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _setFilter(_filter.copyWith(query: ''));
                      },
                    ),
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            onChanged: (value) => _setFilter(_filter.copyWith(query: value)),
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final MapEntry(key: kind, value: label) in kinds.entries)
                ChoiceChip(
                  label: Text(label),
                  selected: _filter.kind == kind,
                  onSelected: (_) => _setFilter(_filter.copyWith(kind: kind)),
                ),
              FilterChip(
                label: Text(text.bookmarks_hideNsfw),
                selected: _filter.nsfw == BookmarkNsfw.hide,
                onSelected: (on) => _setFilter(
                  _filter.copyWith(
                    nsfw: on ? BookmarkNsfw.hide : BookmarkNsfw.any,
                  ),
                ),
              ),
              FilterChip(
                label: Text(text.bookmarks_onlyNsfw),
                selected: _filter.nsfw == BookmarkNsfw.only,
                onSelected: (on) => _setFilter(
                  _filter.copyWith(
                    nsfw: on ? BookmarkNsfw.only : BookmarkNsfw.any,
                  ),
                ),
              ),
            ],
          ),
          ListenableBuilder(
            listenable: _pagingController,
            builder: (context, _) {
              final state = _pagingController.value;
              final nothing =
                  _filter.isActive &&
                  !state.isLoading &&
                  !state.hasNextPage &&
                  state.error == null &&
                  (state.pages?.expand((p) => p).isNotEmpty ?? false) &&
                  _matches() == 0;
              return nothing
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Center(child: Text(text.bookmarks_noMatch)),
                    )
                  : const SizedBox.shrink();
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMbin =
        context.read<AppController>().serverSoftware == ServerSoftware.mbin;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isMbin
              ? '${widget.bookmarkList ?? ''} ${l(context).bookmarks}'
              : l(context).bookmarks,
        ),
        actions: [
          // Only Mbin can order its bookmarks.
          if (isMbin)
            PopupMenuButton<BookmarkSort>(
              tooltip: l(context).sort,
              icon: const Icon(Icons.sort),
              initialValue: _sort,
              onSelected: _setSort,
              itemBuilder: (context) => [
                for (final sort in BookmarkSort.values)
                  PopupMenuItem(value: sort, child: Text(_sortLabel(sort))),
              ],
            ),
        ],
      ),
      body: AdvancedPagedScrollView(
        controller: _pagingController,
        leadingSlivers: [SliverToBoxAdapter(child: _filterBar())],
        itemBuilder: (context, item, index) {
          // A hidden item takes no room, so a filter that hides a whole page
          // leaves the list's last item on screen and the next page loads.
          if (!_filter.matches(item as Object)) return const SizedBox.shrink();
          return switch (item) {
            PostModel _ => Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              clipBehavior: Clip.antiAlias,
              child: PostItem(
                item,
                (newValue) => _pagingController.updateItem(item, newValue),
                onTap: () => pushPostPage(
                  context,
                  communityName: item.community.name,
                  postId: item.id,
                  postType: item.type,
                  initData: item,
                  onUpdate: (newValue) =>
                      _pagingController.updateItem(item, newValue),
                ),
                isPreview: item.type == PostType.thread,
                isTopLevel: true,
              ),
            ),
            CommentModel _ => Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: PostComment(
                item,
                (newValue) => _pagingController.updateItem(item, newValue),
                onClick: () => context.router.push(
                  PostCommentRoute(postType: item.postType, commentId: item.id),
                ),
              ),
            ),
            _ => throw UnreachableError(),
          };
        },
      ),
    );
  }

  @override
  void dispose() {
    _pagingController
      ..removeListener(_syncVotes)
      ..dispose();
    _searchController.dispose();
    super.dispose();
  }
}
