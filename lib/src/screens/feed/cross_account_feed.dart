/// One page of results from a single account: items newest-first and the
/// cursor for the next page (null when exhausted).
typedef AccountPage<T> = ({List<T> items, String? next});

class AccountFeedSource<T> {
  AccountFeedSource({required this.account, required this.fetch});

  final String account;
  final Future<AccountPage<T>> Function(String page) fetch;

  List<T> buffer = [];

  /// Empty string is the first page; null means exhausted (or failed).
  String? next = '';
  Object? error;
}

/// Merges newest-first streams from several accounts. Each source paginates
/// independently and a failing source is dropped without affecting the others.
class CrossAccountFeed<T> {
  CrossAccountFeed({
    required this.sources,
    DateTime Function(T)? createdAt,
    int Function(T, T)? compare,
    this.keyOf,
    this.bufferTarget = 25,
  }) : assert(
         createdAt != null || compare != null,
         'give a createdAt or a compare',
       ),
       _compare = compare ?? ((a, b) => createdAt!(b).compareTo(createdAt(a)));

  final List<AccountFeedSource<T>> sources;

  /// Orders items: negative when the first sorts before the second. Each
  /// source is expected to deliver its items in this order. Defaults to
  /// newest first by [createdAt].
  final int Function(T, T) _compare;

  /// Identity of the logical item (e.g. its ActivityPub id). Items sharing a
  /// key are emitted once; null keys are never merged.
  final String? Function(T)? keyOf;
  final int bufferTarget;
  final Map<String, List<(String, T)>> _copiesByKey = {};

  bool get hasMore => sources.any((s) => s.next != null);

  Iterable<AccountFeedSource<T>> get failed =>
      sources.where((s) => s.error != null);

  /// Returns the next items in order, each paired with its source account.
  /// May be empty while [hasMore] is true; call again.
  Future<List<(String, T)>> fetchNext() async {
    await Future.wait(
      sources
          .where((s) => s.next != null && s.buffer.length <= bufferTarget)
          .map((s) async {
            try {
              final page = await s.fetch(s.next!);
              s
                ..buffer = [...s.buffer, ...page.items]
                ..next = page.next;
            } catch (e) {
              s
                ..error = e
                ..next = null;
            }
          }),
    );

    // Items older than the newest tail of any source that still has pages
    // may be preceded by unfetched items, so only emit down to that bound.
    T? cutoff;
    var hasCutoff = false;
    for (final s in sources.where((s) => s.next != null)) {
      if (s.buffer.isEmpty) return [];
      final tail = s.buffer.last;
      if (!hasCutoff || _compare(tail, cutoff as T) < 0) {
        cutoff = tail;
        hasCutoff = true;
      }
    }

    final out = <(String, T)>[];
    for (final s in sources) {
      // Partition rather than take a prefix: pinned posts can sit out of order.
      final keep = <T>[];
      for (final item in s.buffer) {
        if (!hasCutoff || _compare(item, cutoff as T) <= 0) {
          out.add((s.account, item));
        } else {
          keep.add(item);
        }
      }
      s.buffer = keep;
    }
    out.sort((a, b) => _compare(a.$2, b.$2));

    final key = keyOf;
    if (key == null) return out;
    return out.where((entry) {
      final k = key(entry.$2);
      if (k == null) return true;
      final seen = _copiesByKey[k];
      if (seen == null) {
        _copiesByKey[k] = [entry];
        return true;
      }
      if (!seen.any((c) => c.$1 == entry.$1)) seen.add(entry);
      return false;
    }).toList();
  }

  /// Every account that returned the same logical item as [item] (first is
  /// the one it is displayed under).
  List<String> accountsFor(T item) => copiesFor(item).map((c) => c.$1).toList();

  /// Like [copiesFor] but never empty: an item with no key (or one not seen
  /// here) is only itself, as seen by [account].
  List<(String, T)> copiesOf(String account, T item) {
    final copies = copiesFor(item);
    return copies.isEmpty ? [(account, item)] : copies;
  }

  /// Every (account, copy) pair for the logical item, displayed copy first.
  List<(String, T)> copiesFor(T item) {
    final k = keyOf?.call(item);
    return (k == null ? null : _copiesByKey[k]) ?? const [];
  }
}
