import 'package:flutter_test/flutter_test.dart';
import 'package:interstellar/src/utils/utils.dart';

void main() {
  test('a signed-in account on a normal server can write', () {
    expect(canWriteAs(signedIn: true), isTrue);
  });

  test('a guest cannot write', () {
    expect(canWriteAs(signedIn: false), isFalse);
  });

  test('a copy shown in place of the chosen account cannot be written to', () {
    expect(canWriteAs(signedIn: true, standIn: true), isFalse);
  });

  test('a signed-in Mastodon account can write', () {
    expect(canWriteAs(signedIn: true), isTrue);
  });
}
