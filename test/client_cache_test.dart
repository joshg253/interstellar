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
    cache.rekey('a@x', 'token2');
    final b = cache.get('a@x', 'token2', Object.new);

    expect(identical(a, b), isTrue);
  });

  test('a removed account gets a new client', () {
    final cache = ClientCache<Object>();
    final a = cache.get('a@x', 't', Object.new);
    cache.remove('a@x');
    final b = cache.get('a@x', 't', Object.new);

    expect(identical(a, b), isFalse);
  });
}
