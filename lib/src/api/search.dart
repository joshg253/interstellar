import 'package:flutter/foundation.dart';
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

/// Whether the link [link] is the object with ActivityPub id [apId]: the same
/// server and path, whatever the scheme, case or trailing slash, and without
/// the slug Mbin puts after a thread or post id.
@visibleForTesting
bool sameObject(Uri link, String apId) {
  final other = Uri.tryParse(apId);
  if (other == null || link.host.toLowerCase() != other.host.toLowerCase()) {
    return false;
  }
  List<String> path(Uri u) {
    final seg = [
      for (final s in u.pathSegments)
        if (s.isNotEmpty) s,
    ];
    for (var i = 0; i + 2 < seg.length; i++) {
      if ((seg[i] == 't' || seg[i] == 'p') &&
          int.tryParse(seg[i + 1]) != null &&
          seg[i + 2] != '-') {
        seg.removeAt(i + 2);
        break;
      }
    }
    return seg;
  }

  final a = path(link);
  final b = path(other);
  return a.length == b.length &&
      [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((e) => e);
}

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
      if (apId != null && sameObject(url, apId)) return item;
    }
    // Lemmy and PieFed answer with the one object asked for. Mbin's search
    // also returns posts that merely mention the link, so there it must match.
    return client.software == ServerSoftware.mbin
        ? null
        : found.items.firstOrNull;
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
