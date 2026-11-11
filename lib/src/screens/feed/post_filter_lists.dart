import 'package:interstellar/src/controller/filter_list.dart';
import 'package:interstellar/src/models/post.dart';

/// Applies the active filter lists to [posts]. A post matching a list that is
/// shown with a warning stays, and the list's name goes in [warnings] under
/// the post's (type, id); a post matching any other active list is dropped.
List<PostModel> applyFilterLists(
  List<PostModel> posts, {
  required Map<String, FilterList> lists,
  required Map<String, bool> active,
  required Map<(PostType, int), Set<String>> warnings,
}) {
  return posts.where((post) {
    for (final entry in lists.entries) {
      if (!(active[entry.key] ?? false)) continue;
      final list = entry.value;
      final matches =
          (post.title != null && list.hasMatch(post.title!)) ||
          (post.body != null && list.hasMatch(post.body!));
      if (!matches) continue;
      if (!list.showWithWarning) return false;
      (warnings[(post.type, post.id)] ??= {}).add(entry.key);
    }
    return true;
  }).toList();
}
