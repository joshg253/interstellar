import 'package:flutter_test/flutter_test.dart';
import 'package:interstellar/src/screens/feed/global_subscriptions.dart';

void main() {
  group('communityKey', () {
    test('uses the host and last path segment of the apId', () {
      expect(
        communityKey(
          'https://lemmy.example.com/c/Linux',
          'linux@lemmy.example.com',
          'other.example.com',
        ),
        'linux@lemmy.example.com',
      );
      // mbin magazines live under /m/
      expect(
        communityKey(
          'https://mbin.example.com/m/random',
          'random',
          'mbin.example.com',
        ),
        'random@mbin.example.com',
      );
    });

    test('falls back to the name, adding the account host if bare', () {
      expect(
        communityKey(null, 'random', 'mbin.example.com'),
        'random@mbin.example.com',
      );
      expect(
        communityKey(null, 'linux@lemmy.example.com', 'mbin.example.com'),
        'linux@lemmy.example.com',
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
