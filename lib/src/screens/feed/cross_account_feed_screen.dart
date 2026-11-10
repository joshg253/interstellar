import 'package:expandable/expandable.dart';
import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:interstellar/src/api/api.dart';
import 'package:interstellar/src/api/feed_source.dart';
import 'package:interstellar/src/controller/controller.dart';
import 'package:interstellar/src/controller/server.dart';
import 'package:interstellar/src/models/post.dart';
import 'package:interstellar/src/screens/feed/create_screen.dart';
import 'package:interstellar/src/screens/feed/cross_account_feed.dart';
import 'package:interstellar/src/screens/feed/feed_agregator.dart';
import 'package:interstellar/src/screens/feed/feed_screen.dart'
    show feedSortSelect;
import 'package:interstellar/src/utils/utils.dart' show parseEnum;
import 'package:interstellar/src/widgets/actions.dart';
import 'package:interstellar/src/widgets/floating_menu.dart';
import 'package:interstellar/src/widgets/hide_on_scroll.dart';
import 'package:interstellar/src/widgets/wrapper.dart';
import 'package:interstellar/src/screens/feed/merged_comment_section.dart';
import 'package:interstellar/src/screens/feed/merged_comments.dart';
import 'package:interstellar/src/screens/feed/post_item.dart';
import 'package:interstellar/src/screens/feed/post_page.dart';
import 'package:interstellar/src/widgets/account_avatar.dart';
import 'package:interstellar/src/widgets/account_scope.dart';
import 'package:interstellar/src/screens/feed/global_subscriptions.dart';
import 'package:interstellar/src/screens/feed/feed_accounts.dart';
import 'package:interstellar/src/utils/breakpoints.dart';
import 'package:interstellar/src/widgets/scaffold.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

/// Experimental: newest posts from every account in one stream, rendered with
/// the regular post card (so the usual feed settings apply). Each post is
/// shown through the account chosen in the account menu; the app's selected
/// account is never changed.
class CombinedFeedScreen extends StatefulWidget {
  const CombinedFeedScreen({
    required this.accounts,
    super.key,
    this.scrollController,
  });

  /// Which accounts to draw from; shared with the Feed host.
  final FeedAccounts accounts;

  /// Lets the app shell scroll the feed to the top when its tab is tapped again.
  final ScrollController? scrollController;

  @override
  State<CombinedFeedScreen> createState() => _CombinedFeedScreenState();
}

class _CombinedFeedScreenState extends State<CombinedFeedScreen> {
  late final ScrollController _scroll;
  final _fabKey = GlobalKey<FloatingMenuState>();
  final _items = <(String, PostModel)>[];
  final Map<String, API> _apis = {};
  // Accounts whose API client could not be built, with the reason.
  final Map<String, Object> _apiErrors = {};
  // Locally changed copies (e.g. after a vote), keyed by (account, post id).
  final Map<(String, int), PostModel> _overrides = {};
  CrossAccountFeed<PostModel>? _feed;
  bool _loading = false;
  Object? _setupError;
  late FeedSource _filter;
  late FeedSort _sort;
  // Set by the filter sheet or the floating menu; null follows the settings.
  bool? _hideReadOverride;
  // Each account's server-side "show read posts" (null when it has none).
  final Map<String, bool?> _accountShowRead = {};
  // Accounts left out of the feed (multi-select in the filter sheet).
  final ExpandableController _drawerController = ExpandableController(
    initialExpanded: true,
  );
  // The original Feed drawer's data, for the selected account.
  List<GlobalCommunity> _global = [];
  Map<String, Object> _globalErrors = {};
  bool _globalLoading = false;
  GlobalCommunity? _community;

  @override
  void initState() {
    super.initState();
    _scroll = widget.scrollController ?? ScrollController();
    _scroll.addListener(_onScroll);
    final ac = context.read<AppController>();
    final profile = ac.profile;
    // Start the way the regular Feed does: only the selected account, and its
    // profile's first source when that account is signed in, else All.
    _filter = isAccountSignedIn(ac, ac.selectedAccount)
        ? (profile.feedSourceOrder.firstOrNull ?? FeedSource.all)
        : FeedSource.all;
    _sort = profile.feedDefaultCombinedSort;
    _reset().catchError((Object e) {
      if (mounted) setState(() => _setupError = e);
    });
    () async {
      final ac = context.read<AppController>();
      if (await ac.expandNavDrawer != _drawerController.expanded) {
        if (!mounted) return;
        setState(_drawerController.toggle);
      }
    }();
    _loadGlobal();
    _loadAccountSettings();
  }

  Future<void> _loadGlobal() async {
    setState(() => _globalLoading = true);
    final result = await fetchGlobalSubscriptions(
      context.read<AppController>(),
    );
    if (!mounted) return;
    setState(() {
      _global = result.communities;
      _globalErrors = result.errors;
      _globalLoading = false;
      // keep the selection pointing at the refreshed entry, or drop it
      final key = _community?.key;
      _community = key == null
          ? null
          : _global.where((c) => c.key == key).firstOrNull;
    });
  }

  void _selectCommunity(GlobalCommunity? community) {
    setState(() => _community = community);
    // close the slide-over drawer on narrow layouts
    if (!Breakpoints.isExpanded(context)) Navigator.of(context).pop();
    _reset();
  }

  void _onScroll() {
    // several scroll views can briefly share the shell's controller
    if (!_scroll.hasClients) return;
    if (_scroll.positions.last.extentAfter < 600) _loadMore();
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    // the app shell owns a controller it passed in
    if (widget.scrollController == null) _scroll.dispose();
    super.dispose();
  }

  /// Whether [account] can serve [filter]: personal feeds need a sign-in, and
  /// Some types have no moderated or favorited feed.
  bool _supports(AppController ac, String account, FeedSource filter) {
    if (!_apis.containsKey(account)) return false;
    final needsSignIn =
        filter == FeedSource.subscribed ||
        filter == FeedSource.moderated ||
        filter == FeedSource.favorited;
    if (needsSignIn && !isAccountSignedIn(ac, account)) return false;
    final personal = _apis[account]?.client.software.hasPersonalFeeds ?? false;
    return personal ||
        !(filter == FeedSource.moderated || filter == FeedSource.favorited);
  }

  /// Source, hide-read and per-account choices in one sheet; applied on close.
  Future<void> _openFilters() async {
    final ac = context.read<AppController>();
    var filter = _filter;
    var hideRead = _effectiveHideRead(ac);
    final included = {...widget.accounts.included};

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(16),
            children: [
              Text('Show', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final source in ac.profile.feedSourceOrder)
                    ChoiceChip(
                      avatar: Icon(source.icon, size: 18),
                      label: Text(source.title(context)),
                      selected: filter == source,
                      onSelected: (_) => setSheet(() => filter = source),
                    ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Hide read posts'),
                value: hideRead,
                onChanged: (v) => setSheet(() => hideRead = v),
              ),
              const Divider(),
              // The label, with a select-all box at the right of the same row.
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
                    value:
                        ac.accounts.keys.every(included.contains) &&
                            ac.accounts.isNotEmpty
                        ? true
                        : (ac.accounts.keys.any(included.contains)
                              ? null
                              : false),
                    onChanged: (_) => setSheet(() {
                      if (ac.accounts.keys.every(included.contains)) {
                        included.clear();
                      } else {
                        included.addAll(ac.accounts.keys);
                      }
                    }),
                  ),
                ],
              ),
              for (final account in ac.accounts.keys)
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
        ),
      ),
    );

    if (!mounted) return;
    final sourcesChanged =
        filter != _filter || !setEquals(included, widget.accounts.included);
    final hideChanged = hideRead != _effectiveHideRead(ac);
    if (!sourcesChanged && !hideChanged) return;
    setState(() {
      // picking a different source leaves any single-community view
      if (filter != _filter) _community = null;
      _filter = filter;
      if (hideChanged) _hideReadOverride = hideRead;
    });
    // Ticking down to just the selected account hands over to the original
    // Feed, which disposes this screen, so check before going on.
    widget.accounts.set(included);
    if (!mounted) return;
    // Hiding happens here, so only a change of sources needs a refetch.
    if (sourcesChanged) {
      await _reset();
    } else {
      await _ensureFilled();
    }
  }

  /// Hide-read precedence: this view's own toggle, then the acting account's
  /// server-side setting if it has one, then the Feed defaults setting.
  bool _effectiveHideRead(AppController ac) {
    final override = _hideReadOverride;
    if (override != null) return override;
    final acting = resolveActiveAccount(ac, ac.accounts.keys.toList());
    final show = acting == null ? null : _accountShowRead[acting];
    // The account setting is worded the other way round: show read = off
    // means hide read.
    return show != null ? !show : ac.profile.feedDefaultHideReadPosts;
  }

  /// Items that are shown: read ones are left out when hiding, judged by the
  /// account each post is shown through.
  List<(String, PostModel)> _visible(AppController ac) {
    if (!_effectiveHideRead(ac)) return _items;
    final active = resolveActiveAccount(ac, ac.accounts.keys.toList());
    return _items.where((entry) {
      final copies = _feed?.copiesOf(entry.$1, entry.$2) ?? [entry];
      final (shown, post) = pickCopy(copies, active);
      return !(_overrides[(shown, post.id)] ?? post).read;
    }).toList();
  }

  Future<void> _loadAccountSettings() async {
    final ac = context.read<AppController>();
    await Future.wait([
      for (final account in ac.accounts.keys)
        if (isAccountSignedIn(ac, account))
          () async {
            try {
              final api = await ac.getApiForAccount(account);
              if (!api.client.software.hasPersonalFeeds) return;
              final settings = await api.users.getUserSettings();
              _accountShowRead[account] = settings.showReadPosts;
            } catch (_) {
              // no such setting for this account; fall back to the defaults
            }
          }(),
    ]);
    if (mounted) setState(() {});
  }

  /// After hiding more, keep loading until there is enough to scroll.
  Future<void> _ensureFilled() async {
    if (!mounted) return;
    final ac = context.read<AppController>();
    if (_visible(ac).length < 10 && (_feed?.hasMore ?? false)) {
      await _loadMore();
    }
  }

  void _toggleHideRead() {
    final ac = context.read<AppController>();
    setState(() => _hideReadOverride = !_effectiveHideRead(ac));
    _ensureFilled();
  }

  Future<void> _pickSort() async {
    final picked = await feedSortSelect(context).askSelection(context, _sort);
    if (picked == null || picked == _sort) return;
    setState(() => _sort = picked);
    await _reset();
  }

  Future<void> _reset() async {
    final ac = context.read<AppController>();
    _apiErrors.clear();
    for (final account in ac.accounts.keys) {
      try {
        _apis[account] = await ac.getApiForAccount(account);
      } catch (e) {
        _apis.remove(account);
        _apiErrors[account] = e;
      }
    }
    if (!mounted) return;
    setState(() {
      _items.clear();
      _overrides.clear();
      _setupError = null;
      final filter = _filter;
      final community = _community;
      final sort = _sort;
      final order = postSortFunction(ServerSoftware.lemmy, sort);
      // Plain statements, not a collection literal: nested if/else inside a
      // for-loop attaches the else to the wrong if.
      final sources = <AccountFeedSource<PostModel>>[];
      if (community != null) {
        // one community, through each account that follows it
        for (final entry in community.byAccount.entries) {
          if (!widget.accounts.includes(entry.key)) continue;
          sources.add(
            AccountFeedSource<PostModel>(
              account: entry.key,
              fetch: (page) async {
                final api = _apis[entry.key]!;
                final result = await api.threads.list(
                  FeedSource.community,
                  sourceId: entry.value.id.toString(),
                  page: page.isEmpty ? null : page,
                  sort: sort,
                  combined: api.client.software == ServerSoftware.mbin,
                  // Always ask for read posts too; hiding is done here, by
                  // the effective setting, so it can change without a refetch.
                  showRead: true,
                );
                return (items: result.items, next: result.nextPage);
              },
            ),
          );
        }
      } else {
        for (final account in ac.accounts.keys) {
          if (!widget.accounts.includes(account) ||
              !_supports(ac, account, filter)) {
            continue;
          }
          sources.add(
            AccountFeedSource<PostModel>(
              account: account,
              fetch: (page) async {
                final api = _apis[account]!;
                final mbin = api.client.software == ServerSoftware.mbin;
                final result = await api.threads.list(
                  filter,
                  page: page.isEmpty ? null : page,
                  sort: sort,
                  combined: mbin,
                  showRead: true,
                );
                return (items: result.items, next: result.nextPage);
              },
            ),
          );
        }
      }
      _feed = CrossAccountFeed<PostModel>(
        compare: order,
        keyOf: (p) => p.apId,
        sources: sources,
      );
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    final feed = _feed;
    if (_loading || feed == null || !feed.hasMore) return;
    _loading = true;
    setState(() {});
    try {
      // an iteration can legitimately emit nothing while sources catch up
      for (var i = 0; i < 8 && feed.hasMore; i++) {
        final page = await feed.fetchNext();
        if (!mounted || feed != _feed) return;
        if (page.isNotEmpty) {
          _items.addAll(page);
          // when hiding read posts a page can add nothing visible
          if (_visible(context.read<AppController>()).length >= 10) break;
        }
      }
    } catch (e) {
      _setupError = e;
    } finally {
      if (mounted) {
        _loading = false;
        setState(() {});
        // A refresh swapped the feed while this load ran: load the new one.
        if (feed != _feed) _loadMore();
      }
    }
  }

  /// Starts a new post as the "interact as" account when it can post, else
  /// the first account that can; the screen lets the user switch.
  Future<void> _createPost() async {
    final ac = context.read<AppController>();
    final account = resolveActiveAccount(ac, postingAccounts(ac));
    if (account == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => CreateScreen(account: account)),
    );
  }

  Future<void> _open(String shownAccount, PostModel shownPost) async {
    final ac = context.read<AppController>();
    // Open through the global "interact as" account when it has this post.
    final all =
        _feed?.copiesOf(shownAccount, shownPost) ?? [(shownAccount, shownPost)];
    final (account, post) = pickCopy(
      all,
      resolveActiveAccount(ac, [for (final c in all) c.$1]),
    );
    final api = await ac.getApiForAccount(account);
    final copies = await Future.wait(
      all.where((copy) => copy.$1 != account).map((copy) async {
        final copyApi = await ac.getApiForAccount(copy.$1);
        return (account: copy.$1, api: copyApi, post: copy.$2);
      }),
    );
    // Signed-in accounts without a copy can look the post up when picked.
    final have = {for (final c in all) c.$1};
    final candidates = await Future.wait([
      for (final a in ac.accounts.keys)
        if (!have.contains(a) && isAccountSignedIn(ac, a))
          ac.getApiForAccount(a).then((api) => (account: a, api: api)),
    ]);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AccountScope(
          account: account,
          api: api,
          child: PostPage(
            postType: post.type,
            initData: post,
            onUpdate: (updated) =>
                setState(() => _overrides[(account, post.id)] = updated),
            copies: copies,
            candidates: candidates,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final problems = [
      for (final entry in _apiErrors.entries) '${entry.key}: ${entry.value}',
      for (final s in _feed?.failed ?? <AccountFeedSource<PostModel>>[])
        '${s.account}: ${s.error}',
    ];
    final ac = context.watch<AppController>();
    // Ticked accounts that cannot serve this source (e.g. guests on a
    // personal feed) are left out; say so rather than silently.
    final skipped = _community != null
        ? const <String>[]
        : [
            for (final account in ac.accounts.keys)
              if (widget.accounts.includes(account) &&
                  _apis.containsKey(account) &&
                  !_supports(ac, account, _filter))
                // guests have no name, only the server
                '${isAccountSignedIn(ac, account) ? account : '${account.split('@').last} (guest)'}'
                    ' has no ${_filter.title(context)} feed',
          ];
    // retrying cannot help with the skipped ones
    final canRetry = problems.isNotEmpty;
    problems.addAll(skipped);
    final hideRead = _effectiveHideRead(ac);
    final visible = _visible(ac);
    // The same actions as the regular feed, placed where the profile says.
    ActionLocation place(Enum setting, {bool fallbackToAppBar = false}) =>
        setting.name == 'tabs'
        ? (fallbackToAppBar ? ActionLocation.appBar : ActionLocation.hide)
        : parseEnum(ActionLocation.values, ActionLocation.hide, setting.name);
    final actions = [
      feedActionCreateNew(context).withProps(
        postingAccounts(ac).isEmpty
            ? ActionLocation.hide
            : ac.profile.feedActionCreateNew,
        _createPost,
      ),
      feedActionSetFilter(context).withProps(
        place(ac.profile.feedActionSetFilter, fallbackToAppBar: true),
        _openFilters,
      ),
      feedActionSetSort(context).withProps(
        place(ac.profile.feedActionSetSort, fallbackToAppBar: true),
        _pickSort,
      ),
      feedActionRefresh(context).withProps(ac.profile.feedActionRefresh, () {
        _loadGlobal();
        _reset();
      }),
      feedActionBackToTop(context).withProps(
        ac.profile.feedActionBackToTop,
        () => _scroll.animateTo(
          0,
          duration: Durations.long1,
          curve: Curves.easeInOut,
        ),
      ),
      feedActionExpandFab(context).withProps(
        ac.profile.feedActionExpandFab,
        () => _fabKey.currentState?.toggle(),
      ),
      if (hideRead)
        feedActionShowReadPosts(
          context,
        ).withProps(ac.profile.feedActionHideReadPosts, _toggleHideRead)
      else
        feedActionHideReadPosts(
          context,
        ).withProps(ac.profile.feedActionHideReadPosts, _toggleHideRead),
    ];

    return AdvancedScaffold(
      controller: _drawerController,
      appBar: AppBar(
        leading: Breakpoints.isExpanded(context)
            ? IconButton(
                onPressed: () {
                  setState(_drawerController.toggle);
                  ac.setExpandNavDrawer(_drawerController.expanded);
                },
                icon: const Icon(Symbols.menu_rounded),
              )
            : null,
        // What is shown (source or community) and how it is sorted. The
        // account selector is the rightmost action.
        title: ListTile(
          contentPadding: EdgeInsets.zero,
          title: Row(
            children: [
              if (_community case final c?) ...[
                const Icon(Symbols.group_rounded, size: 20),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(c.first.title, overflow: TextOverflow.ellipsis),
                ),
              ] else ...[
                Icon(_filter.icon, size: 20),
                const SizedBox(width: 4),
                Text(_filter.title(context)),
              ],
            ],
          ),
          subtitle: Row(
            children: [
              Icon(_sort.icon, size: 20),
              const SizedBox(width: 2),
              Text(_sort.title(context)),
            ],
          ),
        ),
        actions: [
          for (final action in actions.where(
            (a) => a.location == ActionLocation.appBar,
          ))
            IconButton(
              tooltip: action.name,
              icon: Icon(action.icon),
              onPressed: action.callback,
            ),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: AccountMenuButton(accounts: ac.accounts.keys.toList()),
          ),
        ],
      ),
      floatingActionButton: Wrapper(
        shouldWrap: ac.profile.hideFeedUIOnScroll,
        parentBuilder: (child) => HideOnScroll(
          controller: _scroll,
          hiddenOffset: const Offset(0, 0.2),
          duration: ac.calcAnimationDuration(),
          child: child,
        ),
        child: FloatingMenu(
          key: _fabKey,
          tapAction: actions
              .where((a) => a.location == ActionLocation.fabTap)
              .firstOrNull,
          holdAction: actions
              .where((a) => a.location == ActionLocation.fabHold)
              .firstOrNull,
          menuActions: actions
              .where((a) => a.location == ActionLocation.fabMenu)
              .toList(),
        ),
      ),
      // The unified list of subscriptions across the accounts. With a single
      // account the original Feed (and its own drawer) is shown instead.
      drawer: GlobalSubscriptionsDrawer(
        communities: _global,
        loading: _globalLoading,
        errors: _globalErrors,
        selected: _community,
        onSelect: _selectCommunity,
      ),
      body: RefreshIndicator(
        onRefresh: _reset,
        child: SelectionArea(
          child: ListView.builder(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: visible.length + 1 + (problems.isEmpty ? 0 : 1),
            itemBuilder: (context, index) {
              if (problems.isNotEmpty && index == 0) {
                return MaterialBanner(
                  content: Text(problems.join('\n')),
                  actions: [
                    if (canRetry)
                      TextButton(onPressed: _reset, child: const Text('Retry'))
                    else
                      const SizedBox.shrink(),
                  ],
                );
              }
              final i = index - (problems.isEmpty ? 0 : 1);
              if (i == visible.length) {
                if (_setupError != null) return Text('$_setupError');
                if (_loading) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (_feed?.hasMore ?? false) {
                  return TextButton(
                    onPressed: _loadMore,
                    child: const Text('Load more'),
                  );
                }
                if (visible.isEmpty) {
                  // Say why instead of showing a blank screen.
                  final used = _feed?.sources.length ?? 0;
                  final where = _community != null
                      ? 'Community: ${_community!.first.title}'
                      : 'Source: ${_filter.title(context)}';
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Text(
                          'No posts to show.',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$where, from $used account(s). Personal sources '
                          'skip guests and accounts that follow nothing.'
                          '${_effectiveHideRead(context.read<AppController>()) ? " Read posts are hidden." : ""}',
                          textAlign: TextAlign.center,
                        ),
                        if (_filter != FeedSource.all || _community != null)
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _filter = FeedSource.all;
                                _community = null;
                              });
                              _reset();
                            },
                            child: const Text('Show all posts'),
                          ),
                      ],
                    ),
                  );
                }
                return const SizedBox(height: 48);
              }
              final (account, post) = visible[i];
              return ValueListenableBuilder<String?>(
                valueListenable: interactAccount,
                builder: (context, _, _) {
                  final ac = context.watch<AppController>();
                  final copies =
                      _feed?.copiesOf(account, post) ?? [(account, post)];
                  // Actions go through the global account's copy when it has
                  // one; otherwise through the first copy, which the card says.
                  final acting = resolveActiveAccount(
                    ac,
                    ac.accounts.keys.toList(),
                  );
                  final (shown, shownPost) = pickCopy(copies, acting);
                  final actingMissing = acting != null && acting != shown;
                  final api = _apis[shown];
                  if (api == null) return const SizedBox.shrink();
                  final key = (shown, shownPost.id);
                  // The app decides how the post looks, not the account:
                  // media from the best copy, your vote state only when it
                  // is the acting account's own.
                  var display = _overrides[key] ?? shownPost;
                  display = display.copyWith(
                    image: bestImage([
                      display.image,
                      for (final c in copies) c.$2.image,
                    ]),
                  );
                  if (actingMissing && _overrides[key] == null) {
                    display = display.copyWith(
                      myVote: null,
                      myBoost: null,
                      bookmarks: null,
                    );
                  }
                  return AccountScope(
                    account: shown,
                    api: api,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        PostItem(
                          display,
                          (updated) =>
                              setState(() => _overrides[key] = updated),
                          onTap: () => _open(account, post),
                          isPreview: true,
                          isTopLevel: true,
                        ),
                        // Which of your accounts have this post.
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            spacing: 4,
                            children: [
                              if (actingMissing)
                                Tooltip(
                                  message:
                                      '$acting has no copy of this post; '
                                      'acting as $shown',
                                  triggerMode: TooltipTriggerMode.tap,
                                  child: Text(
                                    '${acting.split('@').last} → '
                                    '${shown.split('@').last}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ),
                              for (final c in copies)
                                AccountAvatar(c.$1, radius: 9),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
