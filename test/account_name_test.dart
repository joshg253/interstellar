import 'package:flutter_test/flutter_test.dart';
import 'package:interstellar/src/utils/utils.dart';

void main() {
  test('a local name matches the account on any server', () {
    expect(isAccountName('alice', 'alice@example.com'), isTrue);
  });

  test('a host-qualified name matches only the same account', () {
    expect(isAccountName('alice@example.com', 'alice@example.com'), isTrue);
    expect(isAccountName('alice@example.org', 'alice@example.com'), isFalse);
  });

  test('other users do not match', () {
    expect(isAccountName('bob', 'alice@example.com'), isFalse);
    expect(isAccountName('bob@example.com', 'alice@example.com'), isFalse);
  });
}
