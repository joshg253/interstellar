import 'package:http/http.dart' as http;
import 'package:interstellar/src/api/bookmark.dart';
import 'package:interstellar/src/api/client.dart';
import 'package:interstellar/src/api/comments.dart';
import 'package:interstellar/src/api/community.dart';
import 'package:interstellar/src/api/community_moderation.dart';
import 'package:interstellar/src/api/domains.dart';
import 'package:interstellar/src/api/feed.dart';
import 'package:interstellar/src/api/images.dart';
import 'package:interstellar/src/api/messages.dart';
import 'package:interstellar/src/api/microblogs.dart';
import 'package:interstellar/src/api/moderation.dart';
import 'package:interstellar/src/api/notifications.dart';
import 'package:interstellar/src/api/search.dart';
import 'package:interstellar/src/api/threads.dart';
import 'package:interstellar/src/api/users.dart';
import 'package:interstellar/src/controller/server.dart';
import 'package:interstellar/src/utils/globals.dart';
import 'package:interstellar/src/utils/utils.dart';

class API {
  API(this.client)
    : comments = APIComments(client),
      domains = MbinAPIDomains(client),
      threads = APIThreads(client),
      community = APICommunity(client),
      communityModeration = APICommunityModeration(client),
      feed = APIFeed(client),
      messages = APIMessages(client),
      moderation = APIModeration(client),
      notifications = APINotifications(client),
      microblogs = MbinAPIMicroblogs(client),
      search = APISearch(client),
      users = APIUsers(client),
      bookmark = APIBookmark(client),
      images = APIImages(client);

  final ServerClient client;

  final APIComments comments;
  final MbinAPIDomains domains;
  final APIThreads threads;
  final APICommunity community;
  final APICommunityModeration communityModeration;
  final APIFeed feed;
  final APIMessages messages;
  final APIModeration moderation;
  final APINotifications notifications;
  final MbinAPIMicroblogs microblogs;
  final APISearch search;
  final APIUsers users;
  final APIBookmark bookmark;
  final APIImages images;
}

/// nodeinfo software names of servers offering the Mastodon client API.
const _mastodonCompatible = {
  'mastodon',
  'hometown',
  'glitch',
  'glitch-soc',
  'catodon',
  'iceshrimp',
  'sharkey',
  'pleroma',
  'akkoma',
};

/// Reads the software name from a nodeinfo document, or null if it is not one.
ServerSoftware? _softwareFromNodeInfo(http.Response response) {
  try {
    final name =
        ((response.bodyJson['software']! as JsonMap)['name']! as String)
            .toLowerCase();
    // Servers that speak the Mastodon client API share one adapter.
    return _mastodonCompatible.contains(name)
        ? ServerSoftware.mastodon
        : ServerSoftware.values.byName(name);
  } catch (_) {
    return null;
  }
}

/// Detects which software [server] runs. Tries /nodeinfo/2.0.json, then the
/// document /.well-known/nodeinfo points to: some servers (Catodon) answer
/// the first path with their web app's HTML.
Future<ServerSoftware?> getServerSoftware(
  String server, {
  http.Client? client,
}) async {
  final web = client ?? appHttpClient;
  try {
    final direct = _softwareFromNodeInfo(
      await web.get(Uri.https(server, '/nodeinfo/2.0.json')),
    );
    if (direct != null) return direct;

    final discovery = await web.get(Uri.https(server, '/.well-known/nodeinfo'));
    final links = (discovery.bodyJson['links']! as List).cast<JsonMap>();
    // Newest schema first.
    final hrefs =
        links
            .where(
              (l) => (l['rel']! as String).startsWith(
                'http://nodeinfo.diaspora.software/ns/schema/',
              ),
            )
            .map((l) => l['href']! as String)
            .toList()
          ..sort((a, b) => b.compareTo(a));
    for (final href in hrefs) {
      final found = _softwareFromNodeInfo(await web.get(Uri.parse(href)));
      if (found != null) return found;
    }
  } catch (_) {}
  return null;
}
