import 'package:flutter_test/flutter_test.dart';
import 'package:interstellar/src/utils/subscription_matrix.dart';

void main() {
  final matrix = SubscriptionMatrix({
    'a@one.example': {'cats@one.example', 'dogs@two.example'},
    'b@two.example': {'Cats@One.example', 'birds@two.example'},
  });

  test('merges communities case-insensitively and sorts them', () {
    expect(matrix.communities, [
      'birds@two.example',
      'cats@one.example',
      'dogs@two.example',
    ]);
  });

  test('knows who is subscribed', () {
    expect(matrix.isSubscribed('a@one.example', 'CATS@one.example'), isTrue);
    expect(matrix.isSubscribed('a@one.example', 'birds@two.example'), isFalse);
    expect(
      matrix.isSubscribed('nobody@x.example', 'cats@one.example'),
      isFalse,
    );
  });

  test('lists what each account is missing', () {
    expect(matrix.missing('a@one.example'), ['birds@two.example']);
    expect(matrix.missing('b@two.example'), ['dogs@two.example']);
    expect(matrix.missingTotal, 2);
  });

  test('set updates subscriptions', () {
    final m = SubscriptionMatrix({
      'a@one.example': {'cats@one.example'},
      'b@two.example': <String>{},
    });
    m.set('b@two.example', 'cats@one.example', true);
    expect(m.missingTotal, 0);
    m.set('a@one.example', 'cats@one.example', false);
    expect(m.missing('a@one.example'), ['cats@one.example']);
  });

  test('an account with no subscriptions is missing everything', () {
    final m = SubscriptionMatrix({
      'a@one.example': {'cats@one.example'},
      'b@two.example': <String>{},
    });
    expect(m.missing('b@two.example'), ['cats@one.example']);
  });
}
