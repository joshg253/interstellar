import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:interstellar/src/api/feed_source.dart';
import 'package:interstellar/src/api/resolve.dart';
import 'package:interstellar/src/api/notifications.dart';
import 'package:interstellar/src/controller/controller.dart';
import 'package:interstellar/src/controller/router.gr.dart';
import 'package:interstellar/src/controller/server.dart';
import 'package:interstellar/src/models/community.dart';
import 'package:interstellar/src/screens/feed/feed_agregator.dart';
import 'package:interstellar/src/screens/feed/feed_screen.dart';
import 'package:interstellar/src/utils/utils.dart';
import 'package:interstellar/src/widgets/account_avatar.dart';
import 'package:interstellar/src/widgets/avatar.dart';
import 'package:interstellar/src/widgets/loading_button.dart';
import 'package:interstellar/src/widgets/markdown/markdown.dart';
import 'package:interstellar/src/widgets/menus/community_menu.dart';
import 'package:interstellar/src/widgets/notification_control_segment.dart';
import 'package:interstellar/src/widgets/star_button.dart';
import 'package:interstellar/src/widgets/subscription_button.dart';
import 'package:interstellar/src/widgets/tags/tag_widget.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

@RoutePage()
class CommunityScreen extends StatefulWidget {
  const CommunityScreen({
    @PathParam('communityName') required this.communityName,
    this.communityId,
    super.key,
    this.initData,
    this.onUpdate,
  });

  final String communityName;
  final int? communityId;
  final DetailedCommunityModel? initData;
  final void Function(DetailedCommunityModel)? onUpdate;

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  DetailedCommunityModel? _data;

  @override
  void initState() {
    super.initState();

    _data = widget.initData;

    // if (_data == null) {
    (widget.communityId == null
            ? context.read<AppController>().api.community.getByName(
                widget.communityName,
              )
            : context.read<AppController>().api.community.get(
                widget.communityId!,
              ))
        .then((value) {
          if (!mounted) return;
          setState(() {
            _data = value;
          });
        });
    // }
  }

  /// Signed-in accounts, other than the selected one, that could view this
  /// community.
  List<String> _otherAccounts(AppController ac) => [
    for (final account in ac.accounts.keys)
      if (account != ac.selectedAccount &&
          isAccountSignedIn(ac, account) &&
          (ac.servers[account.split('@').last]?.software.canBeAppAccount ??
              false))
        account,
  ];

  /// Looks this community up on [account]'s server and, if found, makes that
  /// the selected account and reopens the community there.
  Future<void> _openAs(String account) async {
    final ac = context.read<AppController>();
    final data = _data!;
    final host = account.split('@').last;
    // Where the community lives: its ActivityPub id is authoritative; the
    // name's host (or the viewing account's server) is the fallback.
    final bare = data.name.split('@').first;
    final apHost = data.apId == null ? null : Uri.tryParse(data.apId!)?.host;
    final origin = (apHost != null && apHost.isNotEmpty)
        ? apHost
        : (data.name.contains('@')
              ? data.name.split('@').last
              : ac.instanceHost);
    final full = '$bare@$origin';
    // a community local to the target server is looked up by its bare name
    final name = origin == host ? bare : full;

    // Held across the switch, which rebuilds the app shell and this page.
    final router = context.router;
    final messenger = ScaffoldMessenger.of(context);
    void fail(String step, Object e) =>
        messenger.showSnackBar(SnackBar(content: Text('$account: $step: $e')));

    DetailedCommunityModel found;
    try {
      final api = await ac.getApiForAccount(account);
      // A community from another server may be unknown to the target: ask it
      // to fetch the community first, and fall back to a plain lookup.
      final fetched = origin != host && data.apId != null
          ? await resolveCommunity(
              api.client,
              data.apId!,
            ).catchError((Object _) => null)
          : null;
      found = fetched ?? await api.community.getByName(name);
    } catch (e) {
      fail('could not find $full', e);
      return;
    }
    try {
      await ac.switchAccounts(account);
      await router.replace(
        CommunityRoute(
          communityName: found.name,
          communityId: found.id,
          initData: found,
        ),
      );
    } catch (e) {
      fail('could not open ${found.name}', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ac = context.watch<AppController>();

    if (_data == null) return Container();
    final others = _otherAccounts(ac);

    final globalName = _data == null
        ? null
        : communityGlobalName(_data!.name, _data!.apId, ac.instanceHost);

    return FeedScreen(
      feedName: _data?.name ?? '',
      feed: FeedAggregator.fromSingleSource(
        name: _data?.name ?? '',
        source: FeedSource.community,
        sourceId: _data?.id.toString(),
      ),
      createPostCommunity: _data,
      details: _data == null
          ? null
          : Padding(
              padding: const EdgeInsets.all(12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final actions = Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SubscriptionButton(
                            isSubscribed: _data!.isUserSubscribed,
                            subscriptionCount: _data!.subscriptionsCount,
                            onSubscribe: (selected) async {
                              final newValue = await ac.api.community.subscribe(
                                _data!.id,
                                selected,
                              );

                              setState(() {
                                _data = newValue;
                              });
                              widget.onUpdate?.call(newValue);
                            },
                            followMode: false,
                          ),
                          StarButton(globalName!),
                          if (others.isNotEmpty)
                            PopupMenuButton<String>(
                              tooltip: 'Open as',
                              icon: const Icon(Symbols.switch_account_rounded),
                              onSelected: _openAs,
                              itemBuilder: (context) => [
                                for (final account in others)
                                  PopupMenuItem<String>(
                                    value: account,
                                    child: Row(
                                      spacing: 8,
                                      children: [
                                        AccountAvatar(account),
                                        Flexible(child: Text(account)),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          if (whenLoggedIn(context, true) ?? false)
                            LoadingIconButton(
                              onPressed: () async {
                                final newValue = await ac.api.community.block(
                                  _data!.id,
                                  !_data!.isBlockedByUser!,
                                );

                                setState(() {
                                  _data = newValue;
                                });
                                widget.onUpdate?.call(newValue);
                              },
                              icon: const Icon(Symbols.block_rounded),
                              style: ButtonStyle(
                                foregroundColor: WidgetStatePropertyAll(
                                  _data!.isBlockedByUser ?? false
                                      ? Theme.of(context).colorScheme.error
                                      : Theme.of(context).disabledColor,
                                ),
                              ),
                            ),
                          IconButton(
                            onPressed: () => showCommunityMenu(
                              context,
                              detailedCommunity: _data,
                              update: (newCommunity) {
                                setState(() {
                                  _data = newCommunity;
                                });
                                widget.onUpdate?.call(newCommunity);
                              },
                            ),
                            icon: const Icon(Symbols.more_vert_rounded),
                          ),
                        ],
                      ),
                      if (_data!.notificationControlStatus != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: NotificationControlSegment(
                            _data!.notificationControlStatus!,
                            (newStatus) async {
                              await ac.api.notifications.updateControl(
                                targetType: NotificationControlUpdateTargetType
                                    .community,
                                targetId: _data!.id,
                                status: newStatus,
                              );

                              final newValue = _data!.copyWith(
                                notificationControlStatus: newStatus,
                              );
                              setState(() {
                                _data = newValue;
                              });
                              widget.onUpdate?.call(newValue);
                            },
                          ),
                        ),
                    ],
                  );

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          if (_data!.icon != null)
                            Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: Avatar(_data!.icon, radius: 32),
                            ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      _data!.title,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleLarge,
                                    ),
                                    if (_data!.isPostingRestrictedToMods)
                                      const PostingRestrictedIndicator(),
                                  ],
                                ),
                                InkWell(
                                  onTap: () async {
                                    await Clipboard.setData(
                                      ClipboardData(text: globalName),
                                    );

                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(l(context).copied),
                                        duration: const Duration(seconds: 2),
                                      ),
                                    );
                                  },
                                  child: Text(globalName),
                                ),
                              ],
                            ),
                          ),
                          if (constraints.maxWidth > 600) actions,
                        ],
                      ),
                      if (constraints.maxWidth <= 600) actions,
                      if (_data!.description != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Markdown(
                            _data!.description!,
                            getNameHost(context, _data!.name),
                          ),
                        ),
                      if (ac.serverSoftware == ServerSoftware.piefed &&
                          _data != null &&
                          _data!.flairs.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Wrap(
                            runSpacing: 5,
                            children: _data!.flairs
                                .map((tag) => TagWidget(tag: tag))
                                .toList(),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
    );
  }
}

class PostingRestrictedIndicator extends StatelessWidget {
  const PostingRestrictedIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Tooltip(
        message: l(context).postingRestricted,
        triggerMode: TooltipTriggerMode.tap,
        child: const Icon(Symbols.lock_rounded, size: 16),
      ),
    );
  }
}
