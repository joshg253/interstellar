import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:interstellar/src/api/api.dart';
import 'package:interstellar/src/controller/controller.dart';
import 'package:interstellar/src/controller/router.gr.dart';
import 'package:interstellar/src/controller/server.dart';
import 'package:interstellar/src/models/comment.dart';
import 'package:interstellar/src/models/post.dart';
import 'package:interstellar/src/utils/globals.dart';
import 'package:interstellar/src/utils/in_app_link.dart';
import 'package:interstellar/src/utils/share.dart';
import 'package:interstellar/src/utils/utils.dart';
import 'package:interstellar/src/widgets/loading_button.dart';
import 'package:interstellar/src/widgets/selection_menu.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

enum LinkAction {
  share,
  copy,
  openInBrowser,
  openInWebview,
  menu;

  Future<void> call(BuildContext context, Uri uri) async {
    switch (this) {
      case LinkAction.share:
        shareUri(uri);
      case LinkAction.copy:
        await Clipboard.setData(ClipboardData(text: uri.toString()));
        if (!context.mounted) return;
        scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(content: Text(l(context).copied), showCloseIcon: true),
        );
      case LinkAction.openInBrowser:
        launchUrl(uri);
      case LinkAction.openInWebview:
        final controller = WebViewController();
        unawaited(controller.setJavaScriptMode(JavaScriptMode.unrestricted));
        unawaited(controller.loadRequest(uri));

        unawaited(context.router.push(WebViewRoute(controller: controller)));
      case LinkAction.menu:
        openWebpageSecondary(context, uri);
    }
  }
}

/// Whether [host] runs Lemmy, PieFed or Mbin, remembered for the session.
final Map<String, Future<bool>> _fediHosts = {};

Future<bool> _isFediHost(AppController ac, String host) {
  if (host == ac.instanceHost) return Future.value(true);
  final known = ac.servers[host]?.software;
  if (known != null) return Future.value(known != ServerSoftware.mastodon);
  return _fediHosts.putIfAbsent(host, () async {
    final software = await getServerSoftware(host);
    return software != null && software != ServerSoftware.mastodon;
  });
}

/// Opens a link to a post, comment, community or user on a Lemmy, PieFed or
/// Mbin server inside the app. Returns false, having done nothing, for any
/// other link or when it cannot be opened, so the caller can fall back.
Future<bool> openLinkInApp(BuildContext context, Uri uri) async {
  final ac = context.read<AppController>();
  final router = context.router;
  final link = parseInAppLink(uri, ownHost: ac.instanceHost);
  if (link == null || ac.api.client.software == ServerSoftware.mastodon) {
    return false;
  }
  try {
    if (!await _isFediHost(ac, uri.host)) return false;
    switch (link) {
      case CommunityLink():
        final c = await ac.api.community.getByName(link.name);
        unawaited(
          router.push(
            CommunityRoute(
              communityName: c.name,
              communityId: c.id,
              initData: c,
            ),
          ),
        );
      case UserLink():
        final u = await ac.api.users.getByName(link.name);
        unawaited(
          router.push(UserRoute(username: u.name, userId: u.id, initData: u)),
        );
      case PostLink():
        final post = link.local ? null : await ac.api.search.resolve(uri);
        if (!link.local && post is! PostModel) return false;
        final id = post is PostModel ? post.id : link.id;
        final type = post is PostModel ? post.type : link.type;
        unawaited(
          router.push(
            type == PostType.thread
                ? ThreadRoute(
                    postId: id,
                    initData: post is PostModel ? post : null,
                  )
                : MicroblogRoute(
                    postId: id,
                    initData: post is PostModel ? post : null,
                  ),
          ),
        );
      case CommentLink():
        final comment = link.local ? null : await ac.api.search.resolve(uri);
        if (!link.local && comment is! CommentModel) return false;
        unawaited(
          router.push(
            PostCommentRoute(
              postType: comment is CommentModel ? comment.postType : link.type,
              commentId: comment is CommentModel ? comment.id : link.id,
            ),
          ),
        );
    }
    return true;
  } catch (_) {
    return false;
  }
}

/// A tapped link: in the app when it points at the fediverse, else the fallback.
Future<void> openLink(
  BuildContext context,
  Uri uri,
  void Function(BuildContext context, Uri uri) fallback,
) async {
  if (await openLinkInApp(context, uri)) return;
  if (context.mounted) fallback(context, uri);
}

void openWebpagePrimary(BuildContext context, Uri uri) => unawaited(
  openLink(
    context,
    uri,
    (ctx, u) =>
        ctx.read<AppController>().profile.defaultLinkAction.call(ctx, u),
  ),
);

void openWebpageSecondary(BuildContext context, Uri uri) => showDialog<String>(
  context: context,
  builder: (BuildContext context) => AlertDialog(
    title: Text(l(context).openLink),
    content: SelectableText(uri.toString()),
    actions: <Widget>[
      OutlinedButton(
        onPressed: () => context.router.pop(),
        child: Text(l(context).cancel),
      ),
      FilledButton.tonal(
        onPressed: () {
          context.router.pop();
          LinkAction.share.call(context, uri);
        },
        child: Text(l(context).share),
      ),
      LoadingTonalButton(
        onPressed: () async {
          await LinkAction.copy.call(context, uri);
          if (!context.mounted) return;
          context.router.pop();
        },
        label: Text(l(context).copy),
      ),
      if (isWebViewSupported)
        FilledButton.tonal(
          onPressed: () {
            context.router.pop();
            LinkAction.openInWebview.call(context, uri);
          },
          child: Text(l(context).webView),
        ),
      FilledButton(
        onPressed: () {
          context.router.pop();
          LinkAction.openInBrowser.call(context, uri);
        },
        child: Text(l(context).browser),
      ),
    ],
    actionsOverflowAlignment: OverflowBarAlignment.center,
    actionsOverflowButtonSpacing: 8,
    actionsOverflowDirection: VerticalDirection.up,
  ),
);

@RoutePage()
class WebViewScreen extends StatelessWidget {
  const WebViewScreen({required this.controller, super.key});

  final WebViewController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: WebViewWidget(controller: controller),
    );
  }
}

SelectionMenu<LinkAction> linkActionSelect(BuildContext context) =>
    SelectionMenu(l(context).setLinkAction, [
      SelectionMenuItem(
        value: LinkAction.share,
        title: l(context).share,
        icon: Symbols.share_rounded,
      ),
      SelectionMenuItem(
        value: LinkAction.copy,
        title: l(context).copy,
        icon: Symbols.copy_all_rounded,
      ),
      SelectionMenuItem(
        value: LinkAction.openInBrowser,
        title: l(context).browser,
        icon: Symbols.open_in_browser_rounded,
      ),
      SelectionMenuItem(
        value: LinkAction.menu,
        title: l(context).openLinkMenu,
        icon: Symbols.menu_rounded,
      ),
    ]);
