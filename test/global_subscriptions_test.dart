import 'package:flutter_test/flutter_test.dart';
import 'package:interstellar/src/screens/feed/global_subscriptions.dart';

void main() {
  group('communityKey', () {
    test('uses the host and last path segment of the apId', () {
      expect(
        communityKey('https://lemmy.ml/c/Linux', 'linux@lemmy.ml', 'lemmy.zip'),
        'linux@lemmy.ml',
      );
      // mbin magazines live under /m/
      expect(
        communityKey('https://fedia.io/m/random', 'random', 'fedia.io'),
        'random@fedia.io',
      );
    });

    test('falls back to the name, adding the account host if bare', () {
      expect(communityKey(null, 'random', 'fedia.io'), 'random@fedia.io');
      expect(
        communityKey(null, 'linux@lemmy.ml', 'fedia.io'),
        'linux@lemmy.ml',
      );
    });
  });

  group('unionByKey', () {
    test('merges the same key across accounts, keeping account order', () {
      final union = unionByKey<String>({
        'a': ['x', 'y'],
        'b': ['y', 'z'],
      }, (account, item) => item);
      expect(union.map((u) => u.key), ['x', 'y', 'z']);
      expect(union.firstWhere((u) => u.key == 'y').byAccount.keys, ['a', 'b']);
      expect(union.firstWhere((u) => u.key == 'z').byAccount.keys, ['b']);
    });
  });
}
