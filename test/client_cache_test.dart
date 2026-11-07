import 'package:flutter_test/flutter_test.dart';
import 'package:interstellar/src/utils/client_cache.dart';

void main() {
  test('the same account and login reuses one client', () {
    final cache = ClientCache<Object>();
    var built = 0;
    Object build() {
      built++;
      return Object();
    }

    final a = cache.get('a@x', 'token1', build);
    final b = cache.get('a@x', 'token1', build);

    expect(identical(a, b), isTrue);
    expect(built, 1);
  });

  test('a changed login builds a new client', () {
    final cache = ClientCache<Object>();
    final a = cache.get('a@x', 'token1', Object.new);
    final b = cache.get('a@x', 'token2', Object.new);

    expect(identical(a, b), isFalse);
  });

  test('accounts do not share clients', () {
    final cache = ClientCache<Object>();
    final a = cache.get('a@x', 't', Object.new);
    final b = cache.get('b@x', 't', Object.new);

    expect(identical(a, b), isFalse);
  });

  test('a refreshed login keeps its client', () {
    final cache = ClientCache<Object>();
    final a = cache.get('a@x', 'token1', Object.new);
    // the stored login is still the one the client was built with
    expect(cache.rekey('a@x', a, 'token1', 'token2'), isTrue);
    final b = cache.get('a@x', 'token2', Object.new);

    expect(identical(a, b), isTrue);
  });

  test('a replaced client cannot rekey its successor', () {
    final cache = ClientCache<Object>();
    final old = cache.get('a@x', 'token1', Object.new);
    // signed in again: the stored login changed, so a new client is built
    final current = cache.get('a@x', 'login2', Object.new);

    expect(cache.rekey('a@x', old, 'login2', 'token2'), isFalse);
    expect(identical(cache.get('a@x', 'login2', Object.new), current), isTrue);
  });

  test('a client is refused while the stored login has moved on', () {
    final cache = ClientCache<Object>();
    final a = cache.get('a@x', 'token1', Object.new);

    // signed in again, but the cached client has not been replaced yet: the
    // old client's refresh must not overwrite the new login
    expect(cache.rekey('a@x', a, 'login2', 'token2'), isFalse);
    expect(identical(cache.get('a@x', 'token1', Object.new), a), isTrue);
  });

  test('a removed account cannot be rekeyed', () {
    final cache = ClientCache<Object>();
    final a = cache.get('a@x', 'token1', Object.new);
    cache.remove('a@x');

    expect(cache.rekey('a@x', a, 'token1', 'token2'), isFalse);
  });

  test('a removed account gets a new client', () {
    final cache = ClientCache<Object>();
    final a = cache.get('a@x', 't', Object.new);
    cache.remove('a@x');
    final b = cache.get('a@x', 't', Object.new);

    expect(identical(a, b), isFalse);
  });
}
