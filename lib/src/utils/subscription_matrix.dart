/// Which accounts are subscribed to which communities, matched by
/// case-insensitive `name@host`.
class SubscriptionMatrix {
  SubscriptionMatrix(Map<String, Set<String>> byAccount)
    : accounts = byAccount.keys.toList() {
    for (final entry in byAccount.entries) {
      final set = <String>{};
      for (final name in entry.value) {
        final key = name.toLowerCase();
        _labels.putIfAbsent(key, () => name);
        set.add(key);
      }
      _subscribed[entry.key] = set;
    }
  }

  final List<String> accounts;
  final Map<String, Set<String>> _subscribed = {};
  final Map<String, String> _labels = {};

  /// Every community any account is subscribed to, sorted.
  List<String> get communities =>
      _labels.values.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  bool isSubscribed(String account, String community) =>
      _subscribed[account]?.contains(community.toLowerCase()) ?? false;

  void set(String account, String community, bool state) {
    final key = community.toLowerCase();
    _labels.putIfAbsent(key, () => community);
    final set = _subscribed.putIfAbsent(account, () => {});
    state ? set.add(key) : set.remove(key);
  }

  /// Communities [account] is not subscribed to but another account is.
  List<String> missing(String account) => [
    for (final community in communities)
      if (!isSubscribed(account, community)) community,
  ];

  /// How many (account, community) pairs are missing.
  int get missingTotal =>
      accounts.fold(0, (sum, account) => sum + missing(account).length);
}
