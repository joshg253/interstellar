import 'package:flutter/material.dart';
import 'package:interstellar/src/controller/controller.dart';
import 'package:interstellar/src/controller/server.dart';
import 'package:interstellar/src/models/comment.dart';
import 'package:interstellar/src/models/community.dart';
import 'package:interstellar/src/models/feed.dart';
import 'package:interstellar/src/models/post.dart';
import 'package:interstellar/src/models/user.dart';
import 'package:interstellar/src/utils/utils.dart';
import 'package:interstellar/src/widgets/account_scope.dart';
import 'package:provider/provider.dart';

/// The host and software that own what is shown: the enclosing account scope's
/// when there is one, else the selected account's. Ids belong to that server.
({String host, ServerSoftware software}) _origin(BuildContext context) {
  final scope = AccountScope.maybeOf(context);
  if (scope != null) {
    return (
      host: scope.account.split('@').last,
      software: scope.api.client.software,
    );
  }
  final ac = context.read<AppController>();
  return (host: ac.instanceHost, software: ac.serverSoftware);
}

/// Local url first, remote url last.
/// Only one link if local is the source. Mastodon has no local url: its ids
/// are made up by the app.
List<Uri> postUrls({
  required String? apId,
  required int id,
  required String communityName,
  required PostType type,
  required String host,
  required ServerSoftware software,
}) {
  final apUrl = apId == null ? null : Uri.tryParse(apId);

  return [
    if (software != ServerSoftware.mastodon &&
        (apUrl == null || apUrl.host != host))
      Uri.https(
        host,
        software == ServerSoftware.mbin
            ? '/m/$communityName/${switch (type) {
                PostType.thread => 't',
                PostType.microblog => 'p',
              }}/$id'
            : '/post/$id',
      ),
    ?apUrl,
  ];
}

List<Uri> genPostUrls(BuildContext context, PostModel post) {
  final origin = _origin(context);
  return postUrls(
    apId: post.apId,
    id: post.id,
    communityName: post.community.name,
    type: post.type,
    host: origin.host,
    software: origin.software,
  );
}

/// Local url first, remote url last.
/// Only one link if local is the source.
List<Uri> commentUrls({
  required String? apId,
  required int id,
  required int postId,
  required String communityName,
  required PostType postType,
  required String host,
  required ServerSoftware software,
}) {
  final apUrl = apId == null ? null : Uri.tryParse(apId);

  return [
    if (software != ServerSoftware.mastodon &&
        (apUrl == null || apUrl.host != host))
      Uri.https(
        host,
        software == ServerSoftware.mbin
            ? '/m/$communityName/${switch (postType) {
                PostType.thread => 't',
                PostType.microblog => 'p',
              }}/$postId/-/${switch (postType) {
                PostType.thread => 'comment',
                PostType.microblog => 'reply',
              }}/$id'
            : '/comment/$id',
      ),
    ?apUrl,
  ];
}

List<Uri> genCommentUrls(BuildContext context, CommentModel comment) {
  final origin = _origin(context);
  return commentUrls(
    apId: comment.apId,
    id: comment.id,
    postId: comment.postId,
    communityName: comment.community.name,
    postType: comment.postType,
    host: origin.host,
    software: origin.software,
  );
}

/// Local url first, remote url last.
/// Only one link if local is the source.
List<Uri> genCommunityUrls(BuildContext context, CommunityModel community) {
  final ac = context.read<AppController>();

  final apUrl = community.apId == null ? null : Uri.tryParse(community.apId!);

  return [
    if (apUrl == null || apUrl.host != ac.instanceHost)
      Uri.https(
        ac.instanceHost,
        ac.serverSoftware == ServerSoftware.mbin
            ? '/m/${community.name}'
            : '/c/${community.name}',
      ),
    ?apUrl,
  ];
}

/// Local url first, remote url last.
/// Only one link if local is the source.
List<Uri> genUserUrls(BuildContext context, UserModel user) {
  final ac = context.read<AppController>();

  final apUrl = user.apId == null ? null : Uri.tryParse(user.apId!);

  return [
    if (apUrl == null || apUrl.host != ac.instanceHost)
      Uri.https(
        ac.instanceHost,
        '/u/${ac.serverSoftware == ServerSoftware.mbin && getNameHost(context, user.name) != ac.instanceHost ? '@' : ''}${user.name}',
      ),
    ?apUrl,
  ];
}

List<Uri> genFeedUrls(BuildContext context, FeedModel feed) {
  final ac = context.read<AppController>();

  final apUrl = feed.apId == null ? null : Uri.tryParse(feed.apId!);

  return [
    if (apUrl == null || apUrl.host != ac.instanceHost)
      Uri.https(ac.instanceHost, '/f/${feed.name}'),
    ?apUrl,
  ];
}
