import 'package:flutter_test/flutter_test.dart';
import 'package:interstellar/src/widgets/markdown/markdown_video.dart';
import 'package:markdown/markdown.dart' as md;

String _html(String source) => md.markdownToHtml(
  source,
  inlineSyntaxes: [VideoMarkdownSyntax(), YoutubeEmbedSyntax()],
);

void main() {
  test('any https address under the video marker becomes a video element', () {
    for (final ext in ['mp4', 'webm', 'MP4', 'x/original']) {
      expect(
        _html('![video/mp4](https://cdn.example.com/v.$ext)'),
        contains('<video>https://cdn.example.com/v.$ext</video>'),
        reason: ext,
      );
    }
  });

  test('a plain image is left alone', () {
    expect(
      _html('![](https://cdn.example.com/a.png)'),
      isNot(contains('video')),
    );
  });

  test('a youtube link card is embedded', () {
    final html = _html('[A clip](https://www.youtube.com/watch?v=dQw4w9WgXcQ)');
    expect(
      html,
      contains('<video>https://www.youtube.com/watch?v=dQw4w9WgXcQ</video>'),
    );
  });
}
