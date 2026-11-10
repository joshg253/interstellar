import 'package:flutter_test/flutter_test.dart';
import 'package:interstellar/src/controller/profile.dart';

void main() {
  test('server names are shown by default', () {
    expect(ProfileRequired.defaultProfile.alwaysShowInstance, isTrue);
  });
}
