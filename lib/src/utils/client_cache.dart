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

  /// Records that [client]'s own login moved on (a token refresh). Does
  /// nothing, and returns false, if [client] is no longer the account's: it was
  /// replaced by a new sign-in or the account was removed.
  bool rekey(String account, C client, String fingerprint) {
    final entry = _entries[account];
    if (entry == null || !identical(entry.$2, client)) return false;
    _entries[account] = (fingerprint, client);
    return true;
  }

  void remove(String account) => _entries.remove(account);
}
