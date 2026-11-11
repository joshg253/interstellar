import 'package:flutter_test/flutter_test.dart';
import 'package:interstellar/src/utils/preview_images.dart';

void main() {
  previewTextTests();
  const url = 'https://example.com/pictrs/image/a.webp';

  test('the first markdown image of a body is the preview image', () {
    final image = firstMarkdownImage(
      '![](  $url  )\n\nText ![b](https://x/b.png)',
    );
    expect(image?.src, url);
    expect(image?.altText, isNull);
  });

  test('alt text and a title are understood', () {
    final image = firstMarkdownImage('![A cat]($url "a title")');
    expect(image?.src, url);
    expect(image?.altText, 'A cat');
  });

  test('videos and bodies without an image give none', () {
    expect(firstMarkdownImage('![](https://x/v.mp4)'), isNull);
    expect(firstMarkdownImage('just text'), isNull);
    expect(firstMarkdownImage(null), isNull);
  });

  test('a preview body leaves out the image syntax', () {
    expect(
      withoutMarkdownImages('![]($url)\n\nThis cat appeared.'),
      'This cat appeared.',
    );
    expect(withoutMarkdownImages('![]($url)'), isNull);
    expect(withoutMarkdownImages('no images'), 'no images');
    expect(withoutMarkdownImages(null), isNull);
  });
}

void previewTextTests() {
  group('previewText', () {
    test('a link shows as its label', () {
      expect(
        previewText('[Comments](https://news.ycombinator.com/item?id=1)'),
        'Comments',
      );
      expect(
        previewText('See [a](https://x/a) and [b](<https://x/b> "t")'),
        'See a and b',
      );
    });

    test('emphasis, code, headings and quotes lose their marks', () {
      expect(
        previewText('**bold** and _it_ and `code` and ~~gone~~'),
        'bold and it and code and gone',
      );
      expect(previewText('# Title\n> quoted'), 'Title\nquoted');
    });

    test('images and raw html are left out; plain text is unchanged', () {
      expect(previewText('![](https://x/a.png)\n\nText'), 'Text');
      expect(previewText('a <b>b</b> c'), 'a b c');
      expect(previewText('snake_case_name 2*3'), 'snake_case_name 2*3');
      expect(previewText(null), isNull);
      expect(previewText('![](https://x/a.png)'), isNull);
    });
  });
}
