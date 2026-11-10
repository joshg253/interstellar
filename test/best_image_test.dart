import 'package:flutter_test/flutter_test.dart';
import 'package:interstellar/src/models/image.dart';
import 'package:interstellar/src/screens/feed/merged_comments.dart';

ImageModel _image(String src, {int? width, int? height}) => ImageModel(
  src: src,
  altText: null,
  blurHash: null,
  blurHashWidth: width,
  blurHashHeight: height,
);

void main() {
  test('prefers an image with known dimensions over a bare thumbnail', () {
    final thumb = _image('thumb');
    final full = _image('full', width: 1200, height: 800);
    expect(bestImage([thumb, full]), same(full));
    expect(bestImage([full, thumb]), same(full));
  });

  test('keeps the first image when none has dimensions', () {
    final a = _image('a');
    final b = _image('b');
    expect(bestImage([a, b]), same(a));
  });

  test('skips copies without an image, and is null with none', () {
    final full = _image('full', width: 10, height: 10);
    expect(bestImage([null, full]), same(full));
    expect(bestImage([null, null]), isNull);
    expect(bestImage(<ImageModel?>[]), isNull);
  });
}
