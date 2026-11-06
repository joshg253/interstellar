import 'package:flutter_test/flutter_test.dart';
import 'package:interstellar/src/widgets/markdown/markdown_mention.dart';
import 'package:markdown/markdown.dart' as md;

/// Renders markdown with the app's mention syntax and GitHub-style autolinks,
/// as the Markdown widget does, and returns the HTML.
String render(String text) => md.markdownToHtml(
  text,
  inlineSyntaxes: [MentionMarkdownSyntax()],
  extensionSet: md.ExtensionSet.gitHubFlavored,
);

void main() {
  spacingTests();
  test('a community mention after a word is a mention, not an email', () {
    final html = render(
      'I am a moderator of the !fallout@lemmy.world and '
      '!falloutmods@lemmy.world communities',
    );
    expect(html, contains('<mention>!fallout@lemmy.world</mention>'));
    expect(html, contains('<mention>!falloutmods@lemmy.world</mention>'));
    expect(html, isNot(contains('mailto:')));
  });

  test('a user mention after a word is a mention', () {
    final html = render('thanks to @fraydabson@lemmy.world for this');
    expect(html, contains('<mention>@fraydabson@lemmy.world</mention>'));
    expect(html, isNot(contains('mailto:')));
  });

  test('mentions still work at the start and after punctuation', () {
    expect(
      render('!fallout@lemmy.world is great'),
      contains('<mention>!fallout@lemmy.world</mention>'),
    );
    expect(
      render('Hello, !fallout@lemmy.world'),
      contains('<mention>!fallout@lemmy.world</mention>'),
    );
  });
}

void spacingTests() {
  test('the space before a mention is kept', () {
    expect(
      render('of the !fallout@lemmy.world and'),
      contains('of the <mention>!fallout@lemmy.world</mention> and'),
    );
    expect(
      render('Hello, !fallout@lemmy.world'),
      contains('Hello, <mention>!fallout@lemmy.world</mention>'),
    );
  });
}
