/// One client per account. Mbin refresh tokens are single use, so two OAuth
/// clients for the same account break each other: the one that refreshes
/// second holds a token the server has already retired.
///
/// A client is reused while the stored login (its fingerprint) is unchanged,
/// and rebuilt when it changes (a new sign-in) or the account is removed. A
/// refresh changes the login too, but the client already has it: [rekey].
class ClientCache<C> {
  final Map<String, (String, C)> _entries = {};

  C get(String account, String fingerprint, C Function() build) {
    final entry = _entries[account];
    if (entry != null && entry.$1 == fingerprint) return entry.$2;
    final client = build();
    _entries[account] = (fingerprint, client);
    return client;
  }

  /// Records that the client's own login moved on (a token refresh).
  void rekey(String account, String fingerprint) {
    final entry = _entries[account];
    if (entry != null) _entries[account] = (fingerprint, entry.$2);
  }

  void remove(String account) => _entries.remove(account);
}
