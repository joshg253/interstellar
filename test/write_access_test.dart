import 'package:flutter_test/flutter_test.dart';
import 'package:interstellar/src/controller/server.dart';
import 'package:interstellar/src/utils/utils.dart';

void main() {
  test('a signed-in account on a normal server can write', () {
    expect(canWriteAs(signedIn: true, software: ServerSoftware.lemmy), isTrue);
  });

  test('a guest cannot write', () {
    expect(
      canWriteAs(signedIn: false, software: ServerSoftware.lemmy),
      isFalse,
    );
  });

  test('a copy shown in place of the chosen account cannot be written to', () {
    expect(
      canWriteAs(signedIn: true, software: ServerSoftware.lemmy, standIn: true),
      isFalse,
    );
  });

  test('a read-only server type cannot write even when it has a login', () {
    expect(
      canWriteAs(signedIn: true, software: ServerSoftware.mastodon),
      isFalse,
    );
  });
}
