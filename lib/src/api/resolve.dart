import 'package:interstellar/src/api/client.dart';
import 'package:interstellar/src/api/mastodon.dart';
import 'package:interstellar/src/controller/server.dart';
import 'package:interstellar/src/models/post.dart';
import 'package:interstellar/src/utils/utils.dart';

/// Asks [client]'s server to fetch the post with ActivityPub id [apId] (if it
/// has not seen it yet) and returns that server's own copy of it, or null if
/// it can't be found or the software doesn't support it.
Future<PostModel?> resolvePost(ServerClient client, String apId) async {
  switch (client.software) {
    case ServerSoftware.lemmy:
      final response = await client.get(
        '/resolve_object',
        queryParams: {'q': apId},
      );
      final post = response.bodyJson['post'];
      if (post == null) return null;
      return PostModel.fromLemmy({
        'post_view': post,
      }, langCodeIdPairs: await client.languageCodeIdPairs());
    case ServerSoftware.piefed:
      final response = await client.get(
        '/resolve_object',
        queryParams: {'q': apId},
      );
      final post = response.bodyJson['post'];
      if (post == null) return null;
      return PostModel.fromPiefed({
        'post_view': post,
      }, langCodeIdPairs: await client.languageCodeIdPairs());
    case ServerSoftware.mastodon:
      // Search lives under /api/v2, outside the client's /api/v1 prefix.
      final uri = Uri.https(client.domain, '/api/v2/search', {
        'q': apId,
        'resolve': 'true',
        'type': 'statuses',
        'limit': '1',
      });
      final response = await client.httpClient.get(uri);
      ServerClient.checkResponseSuccess(uri, response);
      final statuses = (response.bodyJson['statuses'] as List?)
          ?.cast<JsonMap>();
      if (statuses == null || statuses.isEmpty) return null;
      return mastodonPost(statuses.first, client.domain);
    case ServerSoftware.mbin:
      // Not checked whether mbin's API can fetch a remote post by URL.
      return null;
  }
}
