import 'package:interstellar/src/models/image.dart';

final _image = RegExp(r'!\[([^\]]*)\]\(\s*<?([^)\s>]+)>?(?:\s+"[^"]*")?\s*\)');

const _videoExtensions = ['mp4', 'webm', 'mov', 'm4v'];

bool _isVideo(String src) => _videoExtensions.contains(
  Uri.tryParse(src)?.path.split('.').last.toLowerCase(),
);

/// The first `![alt](url)` image in a markdown [body], for a feed preview that
/// shows the body as plain text. Videos written the same way are not images.
ImageModel? firstMarkdownImage(String? body) {
  if (body == null) return null;
  for (final match in _image.allMatches(body)) {
    final src = match.group(2)!;
    if (_isVideo(src)) continue;
    final alt = match.group(1)!.trim();
    return ImageModel(
      src: src,
      altText: alt.isEmpty ? null : alt,
      blurHash: null,
      blurHashWidth: null,
      blurHashHeight: null,
    );
  }
  return null;
}

/// [body] without its markdown image syntax, or null when nothing is left, for
/// a preview that shows the image on its own.
String? withoutMarkdownImages(String? body) {
  if (body == null) return null;
  final text = body.replaceAll(_image, '').trim();
  return text.isEmpty ? null : text;
}

final _link = RegExp(r'\[([^\]]*)\]\(\s*<?[^)\s>]*>?(?:\s+"[^"]*")?\s*\)');
// Each mark is dropped, keeping its first group (the text it wrapped).
final _marks = <RegExp>[
  RegExp(r'<[^>\n]+>'),
  RegExp(r'\*\*(.+?)\*\*'),
  RegExp(r'__(.+?)__'),
  RegExp(r'~~(.+?)~~'),
  RegExp(r'`([^`\n]+)`'),
  RegExp(r'(?<![\w*])\*(?!\s)([^*\n]+?)(?<!\s)\*(?![\w*])'),
  RegExp(r'(?<![\w_])_(?!\s)([^_\n]+?)(?<!\s)_(?![\w_])'),
  RegExp(r'^\s{0,3}#{1,6}\s+', multiLine: true),
  RegExp(r'^\s{0,3}>\s?', multiLine: true),
];

/// [body] as plain text for a list preview, which does not render markdown:
/// images are left out, a link shows as its label, and emphasis, code,
/// headings, quotes and raw html lose their marks. Null when nothing is left.
String? previewText(String? body) {
  var text = withoutMarkdownImages(body);
  if (text == null) return null;
  text = text.replaceAllMapped(_link, (m) => m.group(1)!);
  for (final pattern in _marks) {
    text = text!.replaceAllMapped(
      pattern,
      (m) => m.groupCount > 0 ? m.group(1)! : '',
    );
  }
  text = text!.trim();
  return text.isEmpty ? null : text;
}
