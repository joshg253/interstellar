import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

final _atStatus = RegExp(r'^/@[^/]+/(\d{6,})/?$');
final _usersStatus = RegExp(r'^/users/[^/]+/statuses/(\d{6,})/?$');
final _peertubeShort = RegExp(r'^/w/([A-Za-z0-9]{10,})/?$');
final _peertubeWatch = RegExp(r'^/videos/watch/([0-9a-fA-F-]{20,})/?$');

/// The host and status id when [link] looks like a Mastodon status page
/// (`/@user/123456…` or `/users/user/statuses/123456…`), else null.
(String, String)? mastodonStatusRef(Uri link) {
  if (link.scheme != 'https' || link.host.isEmpty) return null;
  final id =
      (_atStatus.firstMatch(link.path) ?? _usersStatus.firstMatch(link.path))
          ?.group(1);
  return id == null ? null : (link.host, id);
}

/// The host and video id when [link] looks like a PeerTube watch page
/// (`/w/<id>` or `/videos/watch/<uuid>`), else null.
(String, String)? peertubeVideoRef(Uri link) {
  if (link.scheme != 'https' || link.host.isEmpty) return null;
  final id =
      (_peertubeShort.firstMatch(link.path) ??
              _peertubeWatch.firstMatch(link.path))
          ?.group(1);
  return id == null ? null : (link.host, id);
}

/// The gif host the fork resolves, and its API host.
const gifHost = 'redgifs.com';
const _gifApiHost = 'api.$gifHost';

final _gifPage = RegExp(r'^/(?:watch|ifr)/([A-Za-z0-9]+)/?$');

/// The lower-case gif id when [link] is a watch or embed page of the gif
/// host the fork resolves, else null.
String? gifHostRef(Uri link) {
  if (link.scheme != 'https' ||
      (link.host != gifHost && link.host != 'www.$gifHost')) {
    return null;
  }
  return _gifPage.firstMatch(link.path)?.group(1)?.toLowerCase();
}

final _cache = <String, Future<Uri?>>{};

/// A video that [link] points to, from the public API of the server that
/// hosts it: the video or gifv attached to a Mastodon status, or a PeerTube
/// video's file or stream. Null when [link] is neither, there is no video, the
/// server refuses guests, or anything goes wrong. Results are kept per link.
Future<Uri?> linkedVideo(Uri link, http.Client client, {bool useCache = true}) {
  final Future<Uri?> Function() fetch;
  final status = mastodonStatusRef(link);
  final peertube = peertubeVideoRef(link);
  final gif = gifHostRef(link);
  if (gif != null) {
    fetch = () => _gifVideo(gif, client, fresh: !useCache);
  } else if (status != null) {
    fetch = () => _mastodonVideo(status.$1, status.$2, client);
  } else if (peertube != null) {
    fetch = () => _peertubeVideo(peertube.$1, peertube.$2, client);
  } else {
    return Future.value();
  }
  if (!useCache) return fetch();
  return _cache.putIfAbsent(link.toString(), fetch);
}

Future<Object?> _getJson(Uri url, http.Client client) async {
  final response = await client.get(url).timeout(const Duration(seconds: 10));
  if (response.statusCode != 200) return null;
  return jsonDecode(response.body);
}

Uri? _https(Object? value) {
  final url = Uri.tryParse('$value');
  return url != null && url.scheme == 'https' ? url : null;
}

Future<Uri?> _mastodonVideo(String host, String id, http.Client client) async {
  try {
    final json = await _getJson(
      Uri.https(host, '/api/v1/statuses/$id'),
      client,
    );
    final attachments = (json as Map)['media_attachments'];
    if (attachments is! List) return null;
    for (final attachment in attachments) {
      if (attachment is! Map) continue;
      if (attachment['type'] != 'video' && attachment['type'] != 'gifv') {
        continue;
      }
      final url = _https(attachment['url']);
      if (url != null) return url;
    }
  } on Object {
    // best effort: the link stays a link
  }
  return null;
}

Future<Uri?> _peertubeVideo(String host, String id, http.Client client) async {
  try {
    final json = await _getJson(Uri.https(host, '/api/v1/videos/$id'), client);
    final video = json as Map;
    // A plain file plays everywhere; otherwise the adaptive stream.
    final files = video['files'];
    if (files is List) {
      for (final file in files) {
        final url = file is Map ? _https(file['fileUrl']) : null;
        if (url != null) return url;
      }
    }
    final playlists = video['streamingPlaylists'];
    if (playlists is List) {
      for (final playlist in playlists) {
        final url = playlist is Map ? _https(playlist['playlistUrl']) : null;
        if (url != null) return url;
      }
    }
  } on Object {
    // best effort: the link stays a link
  }
  return null;
}

String? _gifToken;
DateTime _gifTokenExpires = DateTime.fromMillisecondsSinceEpoch(0);

/// The host serves a gif's files only with a temporary guest token.
Future<String?> _guestToken(http.Client client, {required bool fresh}) async {
  if (!fresh &&
      _gifToken != null &&
      DateTime.now().isBefore(_gifTokenExpires)) {
    return _gifToken;
  }
  final json = await _getJson(
    Uri.https(_gifApiHost, '/v2/auth/temporary'),
    client,
  );
  final token = json is Map ? json['token'] : null;
  if (token is! String || token.isEmpty) return null;
  _gifToken = token;
  _gifTokenExpires = DateTime.now().add(const Duration(minutes: 30));
  return token;
}

Future<Uri?> _gifVideo(
  String id,
  http.Client client, {
  required bool fresh,
}) async {
  try {
    final token = await _guestToken(client, fresh: fresh);
    if (token == null) return null;
    final response = await client
        .get(
          Uri.https(_gifApiHost, '/v2/gifs/$id'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return null;
    final gif = (jsonDecode(response.body) as Map)['gif'];
    final urls = gif is Map ? gif['urls'] : null;
    if (urls is! Map) return null;
    return _https(urls['hd']) ?? _https(urls['sd']);
  } on Object {
    // best effort: the link stays a link
  }
  return null;
}
