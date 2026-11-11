import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:interstellar/src/api/client.dart';
import 'package:interstellar/src/api/feed_source.dart';
import 'package:interstellar/src/models/comment.dart';
import 'package:interstellar/src/models/community.dart';
import 'package:interstellar/src/models/image.dart';
import 'package:interstellar/src/models/poll.dart';
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

final _htmlTag = RegExp('<(/?)([a-zA-Z][a-zA-Z0-9]*)([^>]*)>');
final _htmlHref = RegExp(
  r'''\bhref\s*=\s*(?:"([^"]*)"|'([^']*)')''',
  caseSensitive: false,
);
final _htmlEntity = RegExp('&(#[xX][0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);');

String _decodeEntities(String text) => text.replaceAllMapped(_htmlEntity, (m) {
  final entity = m[1]!;
  if (entity.startsWith('#')) {
    final code = entity[1] == 'x' || entity[1] == 'X'
        ? int.tryParse(entity.substring(2), radix: 16)
        : int.tryParse(entity.substring(1));
    return code == null ||
            code == 0 ||
            code > 0x10FFFF ||
            (code >= 0xD800 && code <= 0xDFFF)
        ? m[0]!
        : String.fromCharCode(code);
  }
  return switch (entity) {
    'nbsp' => '\u00A0',
    'lt' => '<',
    'gt' => '>',
    'quot' => '"',
    'apos' => "'",
    'amp' => '&',
    _ => m[0]!,
  };
});

/// Status text is plain text in HTML, so any markdown in it is literal. `@`
/// is escaped too, so plain text cannot become one of the app's mention links;
/// real mentions arrive as HTML links and stay links.
String _escapeInline(String text) =>
    text.replaceAllMapped(RegExp(r'[\\`*_\[\]<>~|@]'), (m) => '\\${m[0]}');

/// Markdown that only means something at the start of a line (headings,
/// lists, the app's `:::` blocks).
String _escapeLineStart(String text) => text
    .replaceFirstMapped(RegExp('^(#|[-+]|:::)'), (m) => '\\${m[1]}')
    .replaceFirstMapped(RegExp(r'^(\d+)([.)])'), (m) => '${m[1]}\\${m[2]}');

/// Only web links are followed; anything else (javascript:, data:, ...) is
/// dropped.
String? _safeWebUrl(String? url) {
  if (url == null) return null;
  final uri = Uri.tryParse(url.trim());
  if (uri == null ||
      !(uri.isScheme('http') || uri.isScheme('https')) ||
      uri.host.isEmpty) {
    return null;
  }
  return uri.toString();
}

String _markdownTarget(String url) => url
    .replaceAll('(', '%28')
    .replaceAll(')', '%29')
    .replaceAll('<', '%3C')
    .replaceAll('>', '%3E')
    .replaceAll(' ', '%20')
    .replaceAll(r'\', '%5C');

/// Statuses are HTML written by remote servers; the app renders markdown.
/// Text is escaped so it cannot become markdown, and only web links are kept.
String mastodonHtmlToMarkdown(String html) {
  final out = StringBuffer();
  var atLineStart = true;
  var inLink = false;
  String? linkTarget;
  final linkText = StringBuffer();

  void text(String raw) {
    var t = _decodeEntities(raw).replaceAll(RegExp(r'\s*\n\s*'), ' ');
    if (inLink) {
      linkText.write(_escapeInline(t));
      return;
    }
    // Whitespace is significant in a status (a picture made of emoji), but
    // markdown collapses runs of spaces and drops them at a line start, so
    // they become non-breaking. Only space between tags is dropped.
    if (atLineStart && RegExp(r'^[ \t\r\n]*$').hasMatch(t)) return;
    t = t.replaceAllMapped(RegExp(' {2,}'), (m) => '\u00A0' * m[0]!.length);
    if (atLineStart && t.startsWith(' ')) t = '\u00A0${t.substring(1)}';
    if (t.isEmpty) return;
    var escaped = _escapeInline(t);
    if (atLineStart) escaped = _escapeLineStart(escaped);
    out.write(escaped);
    atLineStart = false;
  }

  void closeLink() {
    if (!inLink) return;
    inLink = false;
    final label = linkText.toString();
    linkText.clear();
    if (label.trim().isEmpty) return;
    if (linkTarget == null) {
      out.write(atLineStart ? _escapeLineStart(label.trimLeft()) : label);
    } else {
      out.write('[$label]($linkTarget)');
    }
    atLineStart = false;
  }

  var pos = 0;
  for (final m in _htmlTag.allMatches(html)) {
    text(html.substring(pos, m.start));
    pos = m.end;
    final closing = m[1] == '/';
    switch (m[2]!.toLowerCase()) {
      case 'br' when !inLink:
        out.write('  \n');
        atLineStart = true;
      case 'p' when closing && !inLink:
        out.write('\n\n');
        atLineStart = true;
      case 'li' when !closing && !inLink:
        out.write(atLineStart ? '- ' : '\n- ');
        atLineStart = false;
      case 'li' when closing && !inLink:
        out.write('\n');
        atLineStart = true;
      case 'a' when !closing:
        closeLink();
        inLink = true;
        final hrefMatch = _htmlHref.firstMatch(m[3]!);
        final href = _decodeEntities(hrefMatch?[1] ?? hrefMatch?[2] ?? '');
        final safe = _safeWebUrl(href);
        linkTarget = safe == null ? null : _markdownTarget(safe);
      case 'a':
        closeLink();
    }
  }
  text(html.substring(pos));
  closeLink();

  // trim() would also strip the non-breaking spaces a picture starts with
  return out
      .toString()
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .replaceAll(RegExp(r'^[ \n\r\t]+'), '')
      .replaceAll(RegExp(r'[ \u00A0\n\r\t]+$'), '');
}

ImageModel? _image(List<JsonMap> media) {
  for (final m in media) {
    if (m['type'] != 'image') continue;
    // Processing or uncached remote media has no `url`.
    final src = _safeWebUrl(
      (m['url'] ?? m['remote_url'] ?? m['preview_url']) as String?,
    );
    if (src == null) continue;
    final original = (m['meta'] as JsonMap?)?['original'] as JsonMap?;
    return ImageModel(
      src: src,
      altText: m['description'] as String?,
      blurHash: m['blurhash'] as String?,
      blurHashWidth: original?['width'] as int?,
      blurHashHeight: original?['height'] as int?,
    );
  }
  return null;
}

/// Video and gifv attachments (a gifv is a looping mp4) as markdown the body's
/// video player renders.
String _videos(List<JsonMap> media) => [
  for (final m in media)
    if (m['type'] == 'video' || m['type'] == 'gifv')
      if (_safeWebUrl((m['url'] ?? m['remote_url']) as String?) case final src?
          when src.startsWith('https:'))
        '![video/mp4](${_markdownTarget(src)})',
].join('\n\n');

ImageModel? _avatar(String? url) {
  final src = _safeWebUrl(url);
  return src == null
      ? null
      : ImageModel(
          src: src,
          altText: null,
          blurHash: null,
          blurHashWidth: null,
          blurHashHeight: null,
        );
}

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

/// A content warning hides the text behind the app's spoiler block. The
/// warning is plain text, but the block renders its first line as markdown, so
/// it is escaped.
String _body(JsonMap s) {
  final warning = _escapeInline(
    ((s['spoiler_text'] as String?) ?? '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim(),
  );
  final videos = _videos(((s['media_attachments'] as List?) ?? []).cast());
  final text = [
    mastodonHtmlToMarkdown((s['content'] as String?) ?? ''),
    videos,
  ].where((p) => p.isNotEmpty).join('\n\n');
  return warning.isEmpty ? text : '::: spoiler $warning\n$text\n:::';
}

/// The link card as a markdown link. Its title comes from the linked page, so
/// it is escaped like any other text.
String? _cardLink(JsonMap? card) {
  final url = _safeWebUrl(card?['url'] as String?);
  if (url == null) return null;
  final title = ((card?['title'] as String?) ?? '').trim();
  return '[${_escapeInline(title.isEmpty ? url : title)}]'
      '(${_markdownTarget(url)})';
}

PostModel mastodonPost(JsonMap json, String domain) {
  // A boost is shown as the status that was boosted.
  final s = (json['reblog'] as JsonMap?) ?? json;
  final created = DateTime.parse(s['created_at']! as String);
  final cardLink = _cardLink(s['card'] as JsonMap?);

  return PostModel(
    type: PostType.microblog,
    id: mastodonId(domain, s['id']! as String),
    user: _user(s['account']! as JsonMap, domain),
    community: _community(domain),
    domain: null,
    title: null,
    url: null,
    image: _image(((s['media_attachments'] as List?) ?? []).cast<JsonMap>()),
    body: cardLink == null ? _body(s) : '${_body(s)}\n\n$cardLink',
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
    bookmarks: [if ((s['bookmarked'] as bool?) ?? false) ''],
    read: false,
    crossPosts: [],
    flairs: [],
    poll: s['poll'] == null
        ? null
        : PollModel.fromMastodon(
            mastodonId(domain, s['id']! as String),
            s['poll']! as JsonMap,
          ),
    event: null,
    apId: (s['uri'] ?? s['url']) as String?,
    emojiReactions: null,
  );
}

/// One status as a comment on the post [rootRaw]. [parentRaw] and [topRaw] are
/// the comment it replies to and the top-level comment above it: null for a
/// direct reply to the post (as on Lemmy and PieFed), or when not known.
/// [children] are its replies, when known.
CommentModel mastodonComment(
  JsonMap d,
  String domain, {
  required String rootRaw,
  String? parentRaw,
  String? topRaw,
  List<CommentModel> children = const [],
}) {
  final created = DateTime.parse(d['created_at']! as String);
  return CommentModel(
    id: mastodonId(domain, d['id']! as String),
    user: _user(d['account']! as JsonMap, domain),
    community: _community(domain),
    postType: PostType.microblog,
    postId: mastodonId(domain, rootRaw),
    rootId: topRaw == null ? null : mastodonId(domain, topRaw),
    parentId: parentRaw == null ? null : mastodonId(domain, parentRaw),
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
    bookmarks: [if ((d['bookmarked'] as bool?) ?? false) ''],
    apId: (d['uri'] ?? d['url']) as String?,
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

  // [parentRaw] and [topRaw] are null for a direct reply to the post, as
  // the parent and root of a top-level comment are on Lemmy and PieFed.
  CommentModel build(JsonMap d, String? parentRaw, String? topRaw) {
    final raw = d['id']! as String;
    return mastodonComment(
      d,
      domain,
      rootRaw: rootRaw,
      parentRaw: parentRaw,
      topRaw: topRaw,
      children: [
        for (final c in byParent[raw] ?? []) build(c, raw, topRaw ?? raw),
      ],
    );
  }

  return [for (final d in byParent[rootRaw] ?? []) build(d, null, null)];
}

/// `name@host` of the accounts that are groups (what Lemmy, PieFed and Mbin
/// communities look like to Mastodon) or, with [groups] false, of all others.
Set<String> mastodonAccountNames(
  List<JsonMap> accounts,
  String accountHost, {
  required bool groups,
}) => {
  for (final a in accounts)
    if ((a['group'] as bool? ?? false) == groups)
      normalizeName(a['acct']! as String, accountHost),
};

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
        } on Exception catch (e) {
          // Only a refusal falls back; a server error or a dead network
          // must not be shown as trending posts under another name.
          if (page != null || !_refusesGuests(e)) rethrow;
          statuses = _list(
            (await client.get('/trends/statuses', queryParams: query)).body,
          );
          return PostListModel(items: _posts(statuses), nextPage: null);
        }
      case FeedSource.subscribed:
        statuses = _list(
          (await client.get('/timelines/home', queryParams: query)).body,
        );
      case _:
        throw UnsupportedError('Mastodon: ${source.name} feed not supported');
    }

    return PostListModel(
      items: _posts(statuses),
      nextPage: statuses.isEmpty ? null : statuses.last['id']! as String,
    );
  }

  /// A boost is shown as the status it boosted, so a page can hold the same
  /// post twice; keep the first.
  List<PostModel> _posts(List<JsonMap> statuses) {
    final seen = <int>{};
    return [
      for (final s in statuses) mastodonPost(s, client.domain),
    ].where((post) => seen.add(post.id)).toList();
  }

  /// The server said guests may not read this timeline (401, 403, 422).
  bool _refusesGuests(Exception e) =>
      e is RestrictedAuthException ||
      (e is http.ClientException &&
          RegExp(r'status (401|403|422)\b').hasMatch(e.message));

  /// Every account of a list endpoint, following the `Link` header's `max_id`.
  Future<List<JsonMap>> _accountPages(String path, {int maxPages = 100}) async {
    final out = <JsonMap>[];
    String? maxId;
    var pages = 0;
    do {
      final response = await client.get(
        path,
        queryParams: {'limit': '80', 'max_id': maxId},
      );
      out.addAll(_list(response.body));
      final next = RegExp(
        r'<([^>]*)>\s*;\s*rel="next"',
      ).firstMatch(response.headers['link'] ?? '')?[1];
      maxId = next == null ? null : Uri.parse(next).queryParameters['max_id'];
    } while (maxId != null && ++pages < maxPages);
    return out;
  }

  /// The accounts the signed-in user follows (needs a token).
  Future<List<JsonMap>> following() async {
    final me = (await client.get('/accounts/verify_credentials')).bodyJson;
    return _accountPages('/accounts/${me['id']}/following');
  }

  /// The accounts the signed-in user blocks (needs a token).
  Future<List<JsonMap>> blocked() => _accountPages('/blocks');

  /// Finds the account for `name@host`, asking the server to look it up on
  /// the other server if it has not seen it.
  Future<String> resolveAccount(String acct) async {
    final response = await client.get(
      '/accounts/search',
      queryParams: {'q': acct, 'resolve': 'true', 'limit': '1'},
    );
    final found = _list(response.body);
    if (found.isEmpty) throw Exception('No such account');
    return found.first['id']! as String;
  }

  Future<void> setFollow(String id, bool state) async {
    await client.post('/accounts/$id/${state ? 'follow' : 'unfollow'}');
  }

  Future<void> setBlock(String id, bool state) async {
    await client.post('/accounts/$id/${state ? 'block' : 'unblock'}');
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

  Future<JsonMap> setBookmark(int id, bool state) async => (await client.post(
    '/statuses/${mastodonRawId(id)}/${state ? 'bookmark' : 'unbookmark'}',
  )).bodyJson;

  /// Bookmarks page by the `Link` header: the ids in it belong to the
  /// bookmarks, not to the statuses.
  Future<(List<PostModel>, String?)> bookmarks({String? page}) async {
    final response = await client.get(
      '/bookmarks',
      queryParams: {'limit': '20', 'max_id': page},
    );
    final next = RegExp(
      r'<([^>]*)>\s*;\s*rel="next"',
    ).firstMatch(response.headers['link'] ?? '')?[1];
    return (
      [for (final s in _list(response.body)) mastodonPost(s, client.domain)],
      next == null ? null : Uri.parse(next).queryParameters['max_id'],
    );
  }

  /// Votes for the options (by index) and returns the status with the new
  /// tallies. The vote goes to the poll's own id, not the status id.
  Future<PostModel> votePoll(int id, List<int> choices) async {
    final status = await _rawStatus(id);
    final poll = status['poll'] as JsonMap?;
    if (poll == null) throw StateError('This post has no poll');
    final updated = (await client.post(
      '/polls/${poll['id']}/votes',
      body: {
        'choices': [for (final c in choices) c.toString()],
      },
    )).bodyJson;
    return mastodonPost({...status, 'poll': updated}, client.domain);
  }

  Future<JsonMap> _rawStatus(int id) async =>
      (await client.get('/statuses/${mastodonRawId(id)}')).bodyJson;

  /// Favorites or unfavorites, like Mbin's toggle: the current state decides.
  Future<JsonMap> toggleFavourite(int id) async {
    final raw = mastodonRawId(id);
    final on = (await _rawStatus(id))['favourited'] == true;
    return (await client.post(
      '/statuses/$raw/${on ? 'unfavourite' : 'favourite'}',
    )).bodyJson;
  }

  /// Boosts or unboosts. The response wraps the boosted status.
  Future<JsonMap> toggleReblog(int id) async {
    final raw = mastodonRawId(id);
    final on = (await _rawStatus(id))['reblogged'] == true;
    final json = (await client.post(
      '/statuses/$raw/${on ? 'unreblog' : 'reblog'}',
    )).bodyJson;
    return (json['reblog'] as JsonMap?) ?? json;
  }

  Future<JsonMap> createStatus(
    String body, {
    String? inReplyTo,
    String? lang,
    bool sensitive = false,
  }) async => (await client.post(
    '/statuses',
    body: {
      'status': body,
      'in_reply_to_id': ?inReplyTo,
      'language': ?lang,
      if (sensitive) 'sensitive': true,
    },
  )).bodyJson;

  Future<JsonMap> editStatus(
    int id,
    String body, {
    String? lang,
    bool? sensitive,
  }) async => (await client.put(
    '/statuses/${mastodonRawId(id)}',
    body: {'status': body, 'language': ?lang, 'sensitive': ?sensitive},
  )).bodyJson;

  Future<void> deleteStatus(int id) async {
    await client.delete('/statuses/${mastodonRawId(id)}');
  }

  Future<void> reportStatus(int id, String reason) async {
    final raw = mastodonRawId(id);
    final accountId = ((await _rawStatus(id))['account']! as JsonMap)['id'];
    await client.post(
      '/reports',
      body: {
        'account_id': accountId,
        'status_ids': [raw],
        'comment': reason,
      },
    );
  }
}
