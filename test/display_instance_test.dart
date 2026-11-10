import 'package:flutter_test/flutter_test.dart';
import 'package:interstellar/src/utils/utils.dart';

void main() {
  test('bare name gets the viewing server when shown', () {
    expect(
      instanceToShow('alice', alwaysShow: true, viewerHost: 'a.example.com'),
      'a.example.com',
    );
  });

  test('qualified name keeps its own host', () {
    expect(
      instanceToShow(
        'alice@b.example.com',
        alwaysShow: true,
        viewerHost: 'a.example.com',
      ),
      'b.example.com',
    );
  });

  test('nothing is added when not shown', () {
    expect(
      instanceToShow('alice', alwaysShow: false, viewerHost: 'a.example.com'),
      isNull,
    );
  });
}
