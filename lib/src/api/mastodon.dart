import 'dart:convert';

import 'package:interstellar/src/api/client.dart';
import 'package:interstellar/src/api/feed_source.dart';
import 'package:interstellar/src/models/comment.dart';
import 'package:interstellar/src/models/community.dart';
import 'package:interstellar/src/models/image.dart';
import 'package:interstellar/src/models/post.dart';
import 'package:interstellar/src/models/user.dart';
import 'package:interstellar/src/utils/models.dart';
import 'package:interstellar/src/utils/utils.dart';

// Mastodon-API accounts (Mastodon and compatible forks) mapped onto the app's
// post/comment models. Statuses become microblog posts; a status's reply
// context becomes a comment tree.

/// Mastodon ids are 18-digit strings, but the app's models use `int` and a JS
/// number is only exact up to 2^53. Map each (server, id) to a stable 52-bit
/// int and remember the original so it can be used in API calls.
final Map<int, String> _rawIds = {};

int mastodonId(String domain, String id) {
  final s = '$domain/$id';
  var h1 = 5381;
  var h2 = 52711;
  for (final c in s.codeUnits) {
    // Kept within 32-bit-safe operations so VM and web agree.
    h1 = ((h1 * 33) + c) & 0xFFFFFFFF;
    h2 = ((h2 * 31) ^ c) & 0xFFFFFFFF;
  }
  final result = (h1 & 0x3FFFFFF) * 0x4000000 + (h2 & 0x3FFFFFF);
  _rawIds[result] = id;
  return result;
}

String mastodonRawId(int id) =>
    _rawIds[id] ??
    (throw StateError('Unknown Mastodon id $id (not seen in this session)'));

/// Statuses are HTML; the app renders markdown.
String mastodonHtmlToMarkdown(String html) {
  var s = html;
  s = s.replaceAllMapped(
    RegExp(r'<a\s[^>]*?href="([^"]*)"[^>]*>(.*?)</a>', dotAll: true),
    (m) => '[${m[2]!.replaceAll(RegExp('<[^>]*>'), '')}](${m[1]})',
  );
  s = s.replaceAll(RegExp(r'<br\s*/?>'), '\n');
  s = s.replaceAll(RegExp(r'</p>\s*<p[^>]*>'), '\n\n');
  s = s.replaceAll(RegExp('<[^>]*>'), '');
  return s
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&')
      .trim();
}

ImageModel? _image(List<JsonMap> media) {
  final m = media
      .where((a) => a['type'] == 'image' || a['type'] == 'gifv')
      .firstOrNull;
  if (m == null) return null;
  final original = (m['meta'] as JsonMap?)?['original'] as JsonMap?;
  return ImageModel(
    src: m['url']! as String,
    altText: m['description'] as String?,
    blurHash: m['blurhash'] as String?,
    blurHashWidth: original?['width'] as int?,
    blurHashHeight: original?['height'] as int?,
  );
}

ImageModel? _avatar(String? url) => url == null || url.isEmpty
    ? null
    : ImageModel(
        src: url,
        altText: null,
        blurHash: null,
        blurHashWidth: null,
        blurHashHeight: null,
      );

DetailedUserModel _user(JsonMap account, String domain) {
  final displayName = account['display_name'] as String?;
  return DetailedUserModel(
    id: mastodonId(domain, account['id']! as String),
    name: account['acct']! as String,
    displayName: displayName == null || displayName.isEmpty
        ? null
        : displayName,
    avatar: _avatar(account['avatar'] as String?),
    cover: _avatar(account['header'] as String?),
    createdAt: DateTime.parse(account['created_at']! as String),
    isBot: (account['bot'] as bool?) ?? false,
    about: account['note'] == null
        ? null
        : mastodonHtmlToMarkdown(account['note']! as String),
    followersCount: account['followers_count'] as int?,
    isFollowedByUser: null,
    isFollowerOfUser: null,
    isBlockedByUser: null,
    notificationControlStatus: null,
    tags: [],
    apId: (account['uri'] ?? account['url']) as String?,
  );
}

/// Microblogs have no community; the author's home server stands in.
CommunityModel _community(String domain) =>
    CommunityModel(id: 0, name: domain, icon: null, apId: null);

String _body(JsonMap s) {
  final spoiler = s['spoiler_text'] as String?;
  final text = mastodonHtmlToMarkdown((s['content'] as String?) ?? '');
  return spoiler == null || spoiler.isEmpty ? text : '**$spoiler**\n\n$text';
}

PostModel mastodonPost(JsonMap json, String domain) {
  // A boost is shown as the status that was boosted.
  final s = (json['reblog'] as JsonMap?) ?? json;
  final created = DateTime.parse(s['created_at']! as String);
  final card = s['card'] as JsonMap?;

  return PostModel(
    type: PostType.microblog,
    id: mastodonId(domain, s['id']! as String),
    user: _user(s['account']! as JsonMap, domain),
    community: _community(domain),
    domain: null,
    title: null,
    url: null,
    image: _image(((s['media_attachments'] as List?) ?? []).cast<JsonMap>()),
    body: card?['url'] == null
        ? _body(s)
        : '${_body(s)}\n\n[${card!['title'] ?? card['url']}](${card['url']})',
    lang: s['language'] as String?,
    numComments: (s['replies_count'] as int?) ?? 0,
    upvotes: s['favourites_count'] as int?,
    downvotes: null,
    boosts: s['reblogs_count'] as int?,
    myVote: (s['favourited'] as bool?) ?? false ? 1 : 0,
    myBoost: s['reblogged'] as bool?,
    isOC: null,
    isNSFW: (s['sensitive'] as bool?) ?? false,
    isPinned: false,
    isLocked: false,
    createdAt: created,
    editedAt: optionalDateTime(s['edited_at'] as String?),
    lastActive: created,
    visibility: PostVisibility.visible,
    canAuthUserModerate: null,
    notificationControlStatus: null,
    bookmarks: null,
    read: false,
    crossPosts: [],
    flairs: [],
    poll: null,
    event: null,
    apId: (s['uri'] ?? s['url']) as String?,
    emojiReactions: null,
  );
}

/// Builds the reply tree from a status's `/context` response. Replies whose
/// parent is not in the response are attached to the root.
List<CommentModel> mastodonCommentTree(
  JsonMap context,
  JsonMap root,
  String domain,
) {
  final rootRaw = root['id']! as String;
  final descendants = ((context['descendants'] as List?) ?? []).cast<JsonMap>();
  final known = {rootRaw, for (final d in descendants) d['id']! as String};

  final byParent = <String, List<JsonMap>>{};
  for (final d in descendants) {
    final parent = d['in_reply_to_id'] as String?;
    byParent
        .putIfAbsent(
          parent != null && known.contains(parent) ? parent : rootRaw,
          () => [],
        )
        .add(d);
  }

  CommentModel build(JsonMap d, String parentRaw) {
    final raw = d['id']! as String;
    final children = [for (final c in byParent[raw] ?? []) build(c, raw)];
    final created = DateTime.parse(d['created_at']! as String);
    return CommentModel(
      id: mastodonId(domain, raw),
      user: _user(d['account']! as JsonMap, domain),
      community: _community(domain),
      postType: PostType.microblog,
      postId: mastodonId(domain, rootRaw),
      rootId: mastodonId(domain, rootRaw),
      parentId: mastodonId(domain, parentRaw),
      image: _image(((d['media_attachments'] as List?) ?? []).cast<JsonMap>()),
      body: _body(d),
      lang: d['language'] as String?,
      isLocked: false,
      upvotes: d['favourites_count'] as int?,
      downvotes: null,
      boosts: d['reblogs_count'] as int?,
      myVote: (d['favourited'] as bool?) ?? false ? 1 : 0,
      myBoost: d['reblogged'] as bool?,
      createdAt: created,
      editedAt: optionalDateTime(d['edited_at'] as String?),
      children: children,
      childCount: children.fold(0, (sum, c) => sum + 1 + c.childCount),
      visibility: PostVisibility.visible,
      canAuthUserModerate: null,
      notificationControlStatus: null,
      bookmarks: null,
      apId: (d['uri'] ?? d['url']) as String?,
      emojiReactions: null,
    );
  }

  return [for (final d in byParent[rootRaw] ?? []) build(d, rootRaw)];
}

class MastodonAPI {
  MastodonAPI(this.client);

  final ServerClient client;

  List<JsonMap> _list(String body) =>
      (jsonDecode(body) as List).cast<JsonMap>();

  /// Newest-first statuses. The public timeline is closed to guests on many
  /// servers, so "all" falls back to trending posts when it is refused.
  Future<PostListModel> timeline(FeedSource source, {String? page}) async {
    final query = {'limit': '20', 'max_id': page};

    List<JsonMap> statuses;
    switch (source) {
      case FeedSource.all:
      case FeedSource.local:
        try {
          statuses = _list(
            (await client.get(
              '/timelines/public',
              queryParams: {
                ...query,
                if (source == FeedSource.local) 'local': 'true',
              },
            )).body,
          );
        } on Exception {
          if (page != null) rethrow;
          statuses = _list(
            (await client.get('/trends/statuses', queryParams: query)).body,
          );
          return PostListModel(
            items: [for (final s in statuses) mastodonPost(s, client.domain)],
            nextPage: null,
          );
        }
      case FeedSource.subscribed:
        statuses = _list(
          (await client.get('/timelines/home', queryParams: query)).body,
        );
      case _:
        throw UnsupportedError('Mastodon: ${source.name} feed not supported');
    }

    return PostListModel(
      items: [for (final s in statuses) mastodonPost(s, client.domain)],
      nextPage: statuses.isEmpty ? null : statuses.last['id']! as String,
    );
  }

  /// The signed-in user (needs a token).
  Future<DetailedUserModel> me() async {
    final response = await client.get('/accounts/verify_credentials');
    return _user(response.bodyJson, client.domain);
  }

  Future<PostModel> status(int id) async {
    final raw = mastodonRawId(id);
    final response = await client.get('/statuses/$raw');
    return mastodonPost(response.bodyJson, client.domain);
  }

  Future<CommentListModel> comments(int postId) async {
    final raw = mastodonRawId(postId);
    final response = await client.get('/statuses/$raw/context');
    return CommentListModel(
      items: mastodonCommentTree(response.bodyJson, {'id': raw}, client.domain),
      nextPage: null,
    );
  }
}
