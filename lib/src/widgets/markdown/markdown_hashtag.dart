import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart' as mdf;
import 'package:interstellar/src/api/feed_source.dart';
import 'package:interstellar/src/controller/router.gr.dart';
import 'package:interstellar/src/screens/feed/feed_agregator.dart';
import 'package:markdown/markdown.dart' as md;

class HashtagMarkdownSyntax extends md.InlineSyntax {
  HashtagMarkdownSyntax() : super(_tagPattern);

  /*
    This expression checks the following:
    
    - Ensure there is no more than one # at the start.
    - Ensure there is not a word character preceding the match.
    - Match only word characters after the #.
    - Don't match if there are only digits after the #.
    - Ensure the match ends at the end of the whole set of word characters.
    - Ensure there is not a # immediately following the match.

    Dart's \w, \b and \B know only ASCII, and the markdown package builds the
    pattern without the unicode flag (so no \p{L}); accented letters, which
    include combining marks, and other scripts are listed as ranges instead.
   */
  static const String _word =
      r'\w\u00C0-\u00D6\u00D8-\u00F6\u00F8-\u1FFF\u3040-\uD7FF';
  static const String _tagPattern =
      '(?<![#$_word])#(?!\\d+(?![$_word]))([$_word]+)(?![$_word#])';

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final tag = match.group(0);

    final node = md.Element.text('tag', tag ?? 'unknown');

    parser.addNode(node);

    return true;
  }
}

class HashtagMarkdownBuilder extends mdf.MarkdownElementBuilder {
  HashtagMarkdownBuilder();

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    return RichText(
      text: TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: HashtagWidget(element.textContent),
          ),
        ],
      ),
    );
  }
}

class HashtagWidget extends StatelessWidget {
  const HashtagWidget(this.tag, {super.key});

  final String tag;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: InkWell(
              child: Text(tag, style: const TextStyle(color: Colors.blue)),
              onTap: () => context.router.push(
                FeedRoute(
                  feedName: tag,
                  feed: FeedAggregator.fromSingleSource(
                    name: tag,
                    source: FeedSource.tag,
                    sourceId: tag,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
