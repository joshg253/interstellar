import 'package:interstellar/src/api/client.dart';
import 'package:interstellar/src/api/mastodon.dart';
import 'package:interstellar/src/controller/server.dart';
import 'package:interstellar/src/models/community.dart';
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
      // The search can fall back to unrelated statuses; only the one asked
      // for is a copy.
      final status = statuses.first;
      if (status['uri'] != apId && status['url'] != apId) return null;
      return mastodonPost(status, client.domain);
    case ServerSoftware.mbin:
      // Search by URL returns the matching ActivityPub objects (fetching them
      // if unknown): threads, microblogs and comments mixed together.
      final response = await client.get('/search', queryParams: {'q': apId});
      final objects = (response.bodyJson['apObjects'] as List?)
          ?.cast<JsonMap>();
      if (objects == null) return null;
      for (final object in objects) {
        // Search may return other objects too; only the one asked for counts.
        if (object['apId'] != apId) continue;
        if (object['commentId'] != null) continue;
        if (object['entryId'] != null) return PostModel.fromMbinEntry(object);
        if (object['postId'] != null) return PostModel.fromMbinPost(object);
      }
      return null;
  }
}

/// Asks [client]'s server to fetch the community with ActivityPub id [apId]
/// (if it has not seen it yet) and returns that server's own copy of it, or
/// null if it can't be found or the software doesn't support it.
Future<DetailedCommunityModel?> resolveCommunity(
  ServerClient client,
  String apId,
) async {
  switch (client.software) {
    case ServerSoftware.lemmy:
    case ServerSoftware.piefed:
      final response = await client.get(
        '/resolve_object',
        queryParams: {'q': apId},
      );
      final community = response.bodyJson['community'];
      if (community == null) return null;
      final json = {'community_view': community};
      return client.software == ServerSoftware.lemmy
          ? DetailedCommunityModel.fromLemmy(json)
          : DetailedCommunityModel.fromPiefed(json);
    case ServerSoftware.mastodon:
    case ServerSoftware.mbin:
      return null;
  }
}
