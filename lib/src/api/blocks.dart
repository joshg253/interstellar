import 'package:interstellar/src/api/api.dart';
import 'package:interstellar/src/api/client.dart';
import 'package:interstellar/src/controller/server.dart';
import 'package:interstellar/src/screens/explore/explore_screen.dart';
import 'package:interstellar/src/utils/utils.dart';

String _named(Map<String, dynamic> actor, String accountHost) {
  // Lemmy calls a person's name `name`; PieFed calls it `user_name`.
  final name = (actor['name'] ?? actor['user_name']) as String?;
  if (name == null) throw Exception('Blocked entry has no name');
  final id = Uri.tryParse(actor['actor_id'] as String? ?? '');
  final host = id == null || id.host.isEmpty ? accountHost : id.host;
  return normalizeName(name, host);
}

/// Reads the blocked communities, or users, out of a Lemmy or PieFed `/site`
/// answer. Throws when the lists are missing, so a server that does not send
/// them is not mistaken for one where nothing is blocked.
Set<String> blockedFromSite(
  Map<String, dynamic> site,
  String accountHost, {
  required bool users,
}) {
  final me = site['my_user'];
  if (me is! Map<String, dynamic>) throw Exception('No my_user in /site');
  final list = me[users ? 'person_blocks' : 'community_blocks'];
  if (list is! List) throw Exception('No block list in /site');
  return {
    for (final item in list)
      _named(
        (item as Map<String, dynamic>)[users ? 'target' : 'community']!
            as Map<String, dynamic>,
        accountHost,
      ),
  };
}

/// What [api]'s account has blocked, as `name@host`.
Future<Set<String>> listBlocked(
  API api,
  String accountHost, {
  required bool users,
}) async {
  if (api.client.software != ServerSoftware.mbin) {
    final site = (await api.client.get('/site')).bodyJson;
    return blockedFromSite(site, accountHost, users: users);
  }
  final names = <String>{};
  String? page;
  do {
    if (users) {
      final res = await api.users.list(
        page: page,
        filter: ExploreFilter.blocked,
      );
      names.addAll(res.items.map((e) => normalizeName(e.name, accountHost)));
      page = res.nextPage;
    } else {
      final res = await api.community.list(
        page: page,
        filter: ExploreFilter.blocked,
      );
      names.addAll(res.items.map((e) => normalizeName(e.name, accountHost)));
      page = res.nextPage;
    }
  } while (page != null);
  return names;
}
