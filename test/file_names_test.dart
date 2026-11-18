import 'package:flutter_test/flutter_test.dart';
import 'package:interstellar/src/utils/file_names.dart';

void main() {
  test('a plain image url is named after its last path segment', () {
    expect(imageFileName('https://example.com/pictrs/image/a.jpeg'), 'a.jpeg');
  });

  test('an image proxy url is named after the image it proxies', () {
    expect(
      imageFileName(
        'https://example.com/api/v4/image_proxy?url='
        'https%3A%2F%2Fexample.org%2Fpictrs%2Fimage%2Fa-b.jpeg',
      ),
      'a-b.jpeg',
    );
  });

  test('the name never has characters Android refuses', () {
    expect(
      imageFileName('https://example.com/a%3Fb.png'),
      isNot(contains('?')),
    );
    expect(imageFileName('https://example.com/'), 'image');
  });
}
