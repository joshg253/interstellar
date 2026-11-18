/// A safe file name for saving or sharing the image at [src]. An image proxy
/// url (`...image_proxy?url=<real url>`) is named after the image it proxies.
String imageFileName(String src) {
  final uri = Uri.tryParse(src);
  final proxied = uri?.queryParameters['url'];
  final segments =
      (proxied == null ? null : Uri.tryParse(proxied))?.pathSegments ??
      uri?.pathSegments ??
      const <String>[];
  final name = segments.lastWhere((s) => s.isNotEmpty, orElse: () => 'image');
  return name.replaceAll(RegExp(r'[\/:*?"<>|]'), '_');
}
