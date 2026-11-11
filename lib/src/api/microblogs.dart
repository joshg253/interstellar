import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:interstellar/src/api/bookmark.dart';
import 'package:interstellar/src/api/client.dart';
import 'package:interstellar/src/api/feed_source.dart';
import 'package:interstellar/src/api/mastodon.dart';
import 'package:interstellar/src/controller/server.dart';
import 'package:interstellar/src/models/post.dart';
import 'package:interstellar/src/utils/utils.dart';

class MbinAPIMicroblogs {
  MbinAPIMicroblogs(this.client);

  final ServerClient client;

  Future<PostListModel> list(
    FeedSource source, {
    String? sourceId,
    String? page,
    FeedSort? sort,
  }) async {
    if (source == FeedSource.favorited) {
      return APIBookmark(
        client,
      ).feedPage(page: page, sort: sort, type: PostType.microblog);
    }
    if (client.software == ServerSoftware.mastodon) {
      return MastodonAPI(client).timeline(source, page: page);
    }
    final path = switch (source) {
      FeedSource.all => '/posts',
      FeedSource.local => '/posts',
      FeedSource.subscribed => '/posts/subscribed',
      FeedSource.moderated => '/posts/moderated',
      FeedSource.favorited => '/posts/favourited',
      FeedSource.community => '/magazine/${sourceId!}/posts',
      FeedSource.user => '/users/${sourceId!}/posts',
      FeedSource.domain => throw Exception(
        'Domain source not allowed for microblog',
      ),
      FeedSource.feed => throw Exception('Feeds source not allowed for mbin'),
      FeedSource.topic => throw Exception('Topics source not allowed for mbin'),
      FeedSource.tag => '/tag/${sourceId!}/posts',
    };

    final query = {
      'p': page,
      if (source == FeedSource.tag) 'sortBy': mbinGetSort(sort)?.name,
      if (source != FeedSource.tag) 'sort': mbinGetSort(sort)?.name,
      'time': mbinGetSortTime(sort),
      if (source == FeedSource.local) 'federation': 'local',
    };

    final response = await client.get(path, queryParams: query);

    return PostListModel.fromMbinPosts(response.bodyJson);
  }

  Future<PostModel> get(int postId) async {
    if (client.software == ServerSoftware.mastodon) {
      return MastodonAPI(client).status(postId);
    }
    final path = '/post/$postId';

    final response = await client.get(path);

    return PostModel.fromMbinPost(response.bodyJson);
  }

  Future<PostModel> putVote(int postID, int choice) async {
    if (client.software == ServerSoftware.mastodon) {
      if (choice != 1) throw UnsupportedError('Mastodon: no downvotes');
      return mastodonPost(
        await MastodonAPI(client).toggleReblog(postID),
        client.domain,
      );
    }
    final path = '/post/$postID/vote/$choice';

    final response = await client.put(path);

    return PostModel.fromMbinPost(response.bodyJson);
  }

  Future<PostModel> putFavorite(int postID) async {
    if (client.software == ServerSoftware.mastodon) {
      return mastodonPost(
        await MastodonAPI(client).toggleFavourite(postID),
        client.domain,
      );
    }
    final path = '/post/$postID/favourite';

    final response = await client.put(path);

    return PostModel.fromMbinPost(response.bodyJson);
  }

  Future<PostModel> edit(
    int postID,
    String body,
    String lang,
    bool isAdult,
  ) async {
    if (client.software == ServerSoftware.mastodon) {
      // The editor holds the rendered markdown, not the status source.
      throw UnsupportedError('Mastodon: editing is not supported yet');
    }
    final path = '/post/$postID';

    final response = await client.put(
      path,
      body: {'body': body, 'lang': lang, 'isAdult': isAdult},
    );

    return PostModel.fromMbinPost(response.bodyJson);
  }

  Future<void> delete(int postID) async {
    if (client.software == ServerSoftware.mastodon) {
      return MastodonAPI(client).deleteStatus(postID);
    }
    final path = '/post/$postID';

    final response = await client.delete(path);
  }

  Future<PostModel> create(
    int communityId, {
    required String body,
    required String lang,
    required bool isAdult,
  }) async {
    if (client.software == ServerSoftware.mastodon) {
      return mastodonPost(
        await MastodonAPI(
          client,
        ).createStatus(body, lang: lang, sensitive: isAdult),
        client.domain,
      );
    }
    final path = '/magazine/$communityId/posts';

    final response = await client.post(
      path,
      body: {'body': body, 'lang': lang, 'isAdult': isAdult},
    );

    return PostModel.fromMbinPost(response.bodyJson);
  }

  Future<PostModel> createImage(
    int communityId, {
    required XFile image,
    required String alt,
    required String body,
    required String lang,
    required bool isAdult,
  }) async {
    if (client.software == ServerSoftware.mastodon) {
      throw UnsupportedError('Mastodon: image posts not supported yet');
    }
    final path = '/magazine/$communityId/posts/image';

    final response = await client.postMultipart(
      path,
      fields: {
        'body': body,
        'lang': lang,
        'isAdult': isAdult.toString(),
        'alt': alt,
      },
      files: {'uploadImage': image},
    );

    return PostModel.fromMbinPost(response.bodyJson);
  }

  Future<void> report(int postId, String reason) async {
    if (client.software == ServerSoftware.mastodon) {
      return MastodonAPI(client).reportStatus(postId, reason);
    }
    final path = '/post/$postId/report';

    final response = await client.post(path, body: {'reason': reason});
  }
}
