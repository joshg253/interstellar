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

final _videoId = RegExp(r'^[A-Za-z0-9_-]{11}$');

// YouTube itself plus the usual alternative front ends (Invidious, Piped).
final _youTubeHost = RegExp(
  r'(^|\.)(youtube(-nocookie)?\.com|yewtu\.be)$|(^|[.-])(invidious|piped|inv)(\.|-|$)',
);

/// The YouTube watch address for an embed or watch link on YouTube or one of
/// its alternative front ends, or null. Other sites are never matched, since
/// their `/embed/<id>` is not a YouTube id.
Uri? youTubeWatchUrl(Uri link) {
  if (link.scheme != 'https' || !_youTubeHost.hasMatch(link.host)) return null;
  final segments = link.pathSegments;
  final id = segments.length == 2 && segments[0] == 'embed'
      ? segments[1]
      : segments.length == 1 && segments[0] == 'watch'
      ? link.queryParameters['v']
      : null;
  if (id == null || !_videoId.hasMatch(id)) return null;
  return Uri.https('www.youtube.com', '/watch', {'v': id});
}
