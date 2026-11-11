const _videoExtensions = ['mp4', 'webm', 'mov', 'm4v'];

/// The address a video player can open for [link], or null if it is not a
/// direct video. Imgur's `.gifv` is a web page; its video is the `.mp4`.
Uri? playableVideoUrl(Uri link) {
  if (link.scheme != 'https') return null;
  final name = link.pathSegments.isEmpty ? '' : link.pathSegments.last;
  final dot = name.lastIndexOf('.');
  if (dot < 0) return null;
  final ext = name.substring(dot + 1).toLowerCase();
  if (_videoExtensions.contains(ext)) return link;
  if (ext == 'gifv' && link.host == 'i.imgur.com') {
    return link.replace(
      pathSegments: [
        ...link.pathSegments.take(link.pathSegments.length - 1),
        '${name.substring(0, dot)}.mp4',
      ],
    );
  }
  return null;
}

/// The video file a server reports for a link (Lemmy's and PieFed's embedded
/// video), or null if it is something a player cannot open: a PeerTube embed
/// is a web page, not a video.
Uri? embeddedVideoFile(String? url) {
  final uri = Uri.tryParse(url ?? '');
  return uri == null ? null : playableVideoUrl(uri);
}
