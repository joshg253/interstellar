import 'package:interstellar/src/models/post.dart';

/// Something a link to a fediverse server points at that the app can open.
sealed class InAppLink {
  const InAppLink();
}

class CommunityLink extends InAppLink {
  /// `name` on the account's own server, `name@host` elsewhere.
  const CommunityLink(this.name);
  final String name;
}

class UserLink extends InAppLink {
  const UserLink(this.name);
  final String name;
}

class PostLink extends InAppLink {
  const PostLink(this.id, this.type, {required this.local});
  final int id;
  final PostType type;

  /// Whether the id is the acting account's own server's. If not, the link
  /// has to be resolved to that server's copy first.
  final bool local;
}

class CommentLink extends InAppLink {
  const CommentLink(this.id, this.type, {required this.local});
  final int id;
  final PostType type;
  final bool local;
}

final _name = RegExp(r'^@?[A-Za-z0-9_.\-]+(@[A-Za-z0-9.\-]+)?$');

String? _qualified(String raw, String linkHost, String ownHost) {
  if (!_name.hasMatch(raw)) return null;
  final name = raw.startsWith('@') ? raw.substring(1) : raw;
  final at = name.indexOf('@');
  final local = at < 0 ? name : name.substring(0, at);
  final host = (at < 0 ? linkHost : name.substring(at + 1)).toLowerCase();
  return host == ownHost.toLowerCase() ? local : '$local@$host';
}

int? _id(String raw) =>
    RegExp(r'^\d{1,9}$').hasMatch(raw) ? int.parse(raw) : null;

/// Reads the path of a link to a Lemmy, PieFed or Mbin server. The caller has
/// checked that the host runs such software. Posts and comments are numbered
/// per server, so for a link to a server other than [ownHost], the host of the
/// account that would open them, the id means nothing: `local` is false.
InAppLink? parseInAppLink(Uri uri, {required String ownHost}) {
  if (uri.scheme != 'https' && uri.scheme != 'http') return null;
  final s = uri.pathSegments.where((e) => e.isNotEmpty).toList();
  if (s.length < 2) return null;
  final own = uri.host.toLowerCase() == ownHost.toLowerCase();

  switch (s[0]) {
    case 'c' || 'm':
      final name = _qualified(s[1], uri.host, ownHost);
      if (name == null) return null;
      if (s[0] == 'm' && s.length >= 4 && (s[2] == 't' || s[2] == 'p')) {
        final id = _id(s[3]);
        if (id == null) return null;
        final type = s[2] == 't' ? PostType.thread : PostType.microblog;
        final comment = s.indexOf('comment');
        if (comment >= 0 && comment + 1 < s.length) {
          final cid = _id(s[comment + 1]);
          return cid == null ? null : CommentLink(cid, type, local: own);
        }
        return PostLink(id, type, local: own);
      }
      return s.length == 2 ? CommunityLink(name) : null;
    case 'u':
      if (s.length != 2) return null;
      final name = _qualified(s[1], uri.host, ownHost);
      return name == null ? null : UserLink(name);
    case 'post' || 'comment':
      if (s.length != 2) return null;
      final id = _id(s[1]);
      if (id == null) return null;
      return s[0] == 'post'
          ? PostLink(id, PostType.thread, local: own)
          : CommentLink(id, PostType.thread, local: own);
  }
  return null;
}
