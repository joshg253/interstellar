import 'package:interstellar/src/models/comment.dart';
import 'package:interstellar/src/models/post.dart';

/// How Mbin orders a bookmark list. Newest and oldest go by when the item was
/// bookmarked. Mbin's other sort options fall back to newest here, so they are
/// not offered.
enum BookmarkSort {
  newest('newest'),
  oldest('oldest'),
  top('top'),
  hot('hot');

  const BookmarkSort(this.mbinValue);

  final String mbinValue;
}

enum BookmarkKind { all, threads, posts, comments }

enum BookmarkNsfw { any, hide, only }

/// Narrows the bookmarks loaded so far. Comments have no NSFW flag, so they
/// pass "hide" and are left out by "only".
class BookmarkFilter {
  const BookmarkFilter({
    this.kind = BookmarkKind.all,
    this.nsfw = BookmarkNsfw.any,
    this.query = '',
  });

  final BookmarkKind kind;
  final BookmarkNsfw nsfw;
  final String query;

  String get _needle => query.trim().toLowerCase();

  bool get isActive =>
      kind != BookmarkKind.all ||
      nsfw != BookmarkNsfw.any ||
      _needle.isNotEmpty;

  BookmarkFilter copyWith({
    BookmarkKind? kind,
    BookmarkNsfw? nsfw,
    String? query,
  }) => BookmarkFilter(
    kind: kind ?? this.kind,
    nsfw: nsfw ?? this.nsfw,
    query: query ?? this.query,
  );

  bool matches(Object item) {
    final parsed = switch (item) {
      PostModel p => (
        p.type == PostType.thread ? BookmarkKind.threads : BookmarkKind.posts,
        p.isNSFW,
        p.title,
        p.body,
      ),
      CommentModel c => (BookmarkKind.comments, false, null, c.body),
      _ => null,
    };

    // what the list cannot show is never let through
    if (parsed == null) return false;
    final (itemKind, isNsfw, title, body) = parsed;

    if (kind != BookmarkKind.all && kind != itemKind) return false;
    if (nsfw == BookmarkNsfw.hide && isNsfw) return false;
    if (nsfw == BookmarkNsfw.only && !isNsfw) return false;
    final needle = _needle;
    if (needle.isEmpty) return true;
    return (title ?? '').toLowerCase().contains(needle) ||
        (body ?? '').toLowerCase().contains(needle);
  }
}
