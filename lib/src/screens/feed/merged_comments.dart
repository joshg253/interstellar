import 'package:interstellar/src/models/image.dart';

/// One logical comment: every account's copy of it, plus the merged replies.
class MergedNode<T> {
  MergedNode(this.copies, this.children);

  /// (account, copy) pairs; the first is the displayed one.
  final List<(String, T)> copies;
  final List<MergedNode<T>> children;
}

/// Merges per-account comment trees into one, matching comments by [keyOf]
/// (an ActivityPub id). Nodes appear in order of first sight across the given
/// accounts, so the first account's ordering leads. Comments without a key
/// are never merged.
List<MergedNode<T>> mergeTrees<T>(
  List<(String account, List<T> items)> lists, {
  required String? Function(T) keyOf,
  required List<T> Function(T) childrenOf,
}) {
  final groups = <List<(String, T)>>[];
  final byKey = <String, List<(String, T)>>{};

  for (final (account, items) in lists) {
    for (final item in items) {
      final key = keyOf(item);
      final group = key == null ? null : byKey[key];
      if (group == null) {
        final fresh = [(account, item)];
        groups.add(fresh);
        if (key != null) byKey[key] = fresh;
      } else if (!group.any((c) => c.$1 == account)) {
        group.add((account, item));
      }
    }
  }

  return groups
      .map(
        (copies) => MergedNode<T>(
          copies,
          mergeTrees<T>(
            [for (final (account, item) in copies) (account, childrenOf(item))],
            keyOf: keyOf,
            childrenOf: childrenOf,
          ),
        ),
      )
      .toList();
}

/// The copy to display and interact with: the [active] account's if it has
/// one, otherwise the first.
(String, T) pickCopy<T>(List<(String, T)> copies, String? active) =>
    copies.firstWhere((c) => c.$1 == active, orElse: () => copies.first);

/// The image to draw for a post that several accounts returned. Servers differ:
/// some give a full image with its size, others a bare thumbnail. Prefer one
/// with known dimensions, so the card looks the same whichever account acts.
ImageModel? bestImage(Iterable<ImageModel?> images) {
  final all = images.nonNulls.toList();
  return all
          .where((i) => i.blurHashWidth != null && i.blurHashHeight != null)
          .firstOrNull ??
      all.firstOrNull;
}
