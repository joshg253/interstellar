import 'package:interstellar/src/api/client.dart';
import 'package:interstellar/src/controller/server.dart';
import 'package:interstellar/src/models/comment.dart';
import 'package:interstellar/src/models/post.dart';
import 'package:interstellar/src/models/search.dart';
import 'package:interstellar/src/screens/explore/explore_screen.dart';

/// Lemmy's and PieFed's resolve_object answers with at most one item of each
/// kind; the search parsers read lists.
Map<String, dynamic> searchShaped(Map<String, dynamic> json) => {
  'posts': [if (json['post'] != null) json['post']],
  'comments': [if (json['comment'] != null) json['comment']],
  'communities': [if (json['community'] != null) json['community']],
  'users': [if (json['person'] != null) json['person']],
  'next_page': null,
};

class APISearch {
  APISearch(this.client);

  final ServerClient client;

  /// Asks this account's server for its copy of the object at [url], fetching
  /// it from the other server if it has not seen it. Null if it has none.
  Future<Object?> resolve(Uri url) async {
    final q = url.toString();
    final SearchListModel found;
    switch (client.software) {
      case ServerSoftware.mastodon:
        throw UnsupportedError('Mastodon: not supported here');
      case ServerSoftware.mbin:
        final response = await client.get('/search', queryParams: {'q': q});
        found = SearchListModel.fromMbin(response.bodyJson);
      case ServerSoftware.lemmy:
        final response = await client.get(
          '/resolve_object',
          queryParams: {'q': q},
        );
        found = SearchListModel.fromLemmy(
          searchShaped(response.bodyJson),
          langCodeIdPairs: await client.languageCodeIdPairs(),
        );
      case ServerSoftware.piefed:
        final response = await client.get(
          '/resolve_object',
          queryParams: {'q': q},
        );
        found = SearchListModel.fromPiefed(
          searchShaped(response.bodyJson),
          langCodeIdPairs: await client.languageCodeIdPairs(),
        );
    }
    for (final item in found.items) {
      final apId = switch (item) {
        PostModel() => item.apId,
        CommentModel() => item.apId,
        _ => null,
      };
      if (apId == q) return item;
    }
    return found.items.firstOrNull;
  }

  Future<SearchListModel> get({
    String? page,
    String? search,
    ExploreFilter? filter,
    int? communityId,
    int? userId,
  }) async {
    switch (client.software) {
      case ServerSoftware.mastodon:
        throw UnsupportedError('Mastodon: not supported here');
      case ServerSoftware.mbin:
        const path = '/search';

        final response = await client.get(
          path,
          queryParams: {
            'p': page,
            'q': search,
            'authorId': userId?.toString(),
            'magazineId': communityId?.toString(),
          },
        );

        return SearchListModel.fromMbin(response.bodyJson);

      case ServerSoftware.lemmy:
        const path = '/search';
        final query = {
          'q': search,
          'page': page ?? '1',
          'type_': 'All',
          'listing_type': switch (filter) {
            ExploreFilter.all => 'All',
            ExploreFilter.local => 'Local',
            _ => 'All',
          },
          'community_id': communityId?.toString(),
          'creator_id': userId?.toString(),
        };

        final response = await client.get(path, queryParams: query);

        final json = response.bodyJson;
        String? nextPage;
        if ((json['comments']! as List<dynamic>).isNotEmpty ||
            (json['posts']! as List<dynamic>).isNotEmpty ||
            (json['communities']! as List<dynamic>).isNotEmpty ||
            (json['users']! as List<dynamic>).isNotEmpty) {
          nextPage = (int.parse(page ?? '1') + 1).toString();
        }

        json['next_page'] = nextPage;

        return SearchListModel.fromLemmy(
          json,
          langCodeIdPairs: await client.languageCodeIdPairs(),
        );

      case ServerSoftware.piefed:
        const path = '/search';
        final query = {
          'q': search,
          'page': page ?? '1',
          // Only use "Posts" type until "All" type is supported in PieFed
          'type_': 'Posts',
          'listing_type': switch (filter) {
            ExploreFilter.all => 'All',
            ExploreFilter.local => 'Local',
            _ => 'All',
          },
          'community_id': communityId?.toString(),
        };

        final response = await client.get(path, queryParams: query);

        final json = response.bodyJson;
        String? nextPage;
        if ((json['comments']! as List<dynamic>).isNotEmpty ||
            (json['posts']! as List<dynamic>).isNotEmpty ||
            (json['communities']! as List<dynamic>).isNotEmpty ||
            (json['users']! as List<dynamic>).isNotEmpty) {
          nextPage = (int.parse(page ?? '1') + 1).toString();
        }

        json['next_page'] = nextPage;

        return SearchListModel.fromPiefed(
          json,
          langCodeIdPairs: await client.languageCodeIdPairs(),
        );
    }
  }
}
