import 'package:flutter_test/flutter_test.dart';
import 'package:interstellar/src/utils/models.dart';

void main() {
  group('mbinFallbackApId', () {
    test('keeps the apId the server gave', () {
      expect(
        mbinFallbackApId(
          'https://other.example/m/x/t/9',
          'https://fedia.io/m/random',
          '/t/1',
        ),
        'https://other.example/m/x/t/9',
      );
    });

    test('builds the id other servers know it by when the apId is null', () {
      expect(
        mbinFallbackApId(null, 'https://fedia.io/m/santafe', '/t/4534187'),
        'https://fedia.io/m/santafe/t/4534187',
      );
      expect(
        mbinFallbackApId(null, 'https://fedia.io/m/random', '/p/6690050'),
        'https://fedia.io/m/random/p/6690050',
      );
    });

    test('stays null when there is nothing to build it from', () {
      expect(mbinFallbackApId(null, null, '/t/1'), isNull);
    });
  });
}
