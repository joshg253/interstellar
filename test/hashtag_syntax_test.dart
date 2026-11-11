import 'package:flutter_test/flutter_test.dart';
import 'package:interstellar/src/widgets/markdown/markdown_hashtag.dart';
import 'package:markdown/markdown.dart' as md;

String _html(String text) =>
    md.markdownToHtml(text, inlineSyntaxes: [HashtagMarkdownSyntax()]);

void main() {
  test('a tag with an umlaut is one tag', () {
    expect(_html('hi #Bär text'), contains('<tag>#Bär</tag>'));
    expect(_html('#Über'), contains('<tag>#Über</tag>'));
  });

  test('a tag with a combining accent is one tag', () {
    const decomposed = 'Bär';
    expect(_html('#$decomposed'), contains('<tag>#$decomposed</tag>'));
  });

  test('tags in other scripts are one tag', () {
    expect(_html('#Привет'), contains('<tag>#Привет</tag>'));
    expect(_html('#日本語'), contains('<tag>#日本語</tag>'));
  });

  test('plain tags still work and stop at punctuation', () {
    expect(_html('#tag, more'), contains('<tag>#tag</tag>'));
    expect(_html('(#tag)'), contains('<tag>#tag</tag>'));
  });

  test('what is not a tag stays text', () {
    expect(_html('#123'), isNot(contains('<tag>')));
    expect(_html('a#tag'), isNot(contains('<tag>')));
    expect(_html('äb#tag'), isNot(contains('<tag>')));
    expect(_html('##tag'), isNot(contains('<tag>')));
    expect(_html('#tag#'), isNot(contains('<tag>')));
  });
}
