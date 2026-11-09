import 'package:interstellar/src/models/image.dart';
import 'package:interstellar/src/utils/utils.dart';

DateTime? optionalDateTime(String? value) =>
    value == null ? null : DateTime.parse(value);

List<String>? optionalStringList(Object? json) =>
    json == null ? null : (json as List<dynamic>).cast<String>();

String? mbinCalcNextPaginationPage(JsonMap pagination) {
  return (pagination['currentPage']! as int) < (pagination['maxPage']! as int)
      ? ((pagination['currentPage']! as int) + 1).toString()
      : null;
}

ImageModel? mbinGetOptionalImage(JsonMap? json) {
  return json == null || (json['storageUrl'] ?? json['sourceUrl']) == null
      ? null
      : ImageModel.fromMbin(json);
}

ImageModel? lemmyGetOptionalImage(
  String? src, [
  String? altText,
  JsonMap? details,
]) {
  return src == null ? null : ImageModel.fromLemmy(src, altText, details);
}

String mbinNormalizeUsername(String username) {
  return username.startsWith('@') ? username.substring(1) : username;
}

/// Converts lemmy and piefed's local name to Mbin's standard name
String getLemmyPiefedActorName(JsonMap json) {
  final name = (json['user_name'] ?? json['name'])! as String;

  return (json['local']! as bool)
      ? name
      : '$name@${Uri.parse(json['actor_id']! as String).host}';
}

String? lemmyCalcNextIntPage(List<dynamic> list, String? currentPage) =>
    list.isEmpty ? null : (int.parse(currentPage ?? '1') + 1).toString();

/// Fills the `apId` Mbin leaves out for its own threads, microblogs and
/// comments, walking [json] (a response body) in place. [origin] is the
/// server the response came from (`https://host`); other servers know the item
/// as `<origin>/m/<magazine>/...`, whether the magazine is local or remote.
void fillMbinApIds(Object? json, String origin) {
  if (json is List) {
    for (final e in json) {
      fillMbinApIds(e, origin);
    }
  } else if (json is Map) {
    final magazine = json['magazine'];
    if (json['apId'] == null &&
        magazine is Map &&
        magazine['magazineId'] != null &&
        magazine['name'] is String) {
      final base = '$origin/m/${magazine['name']}';
      if (json['commentId'] != null) {
        json['apId'] = json['postId'] != null
            ? '$base/p/${json['postId']}/-/reply/${json['commentId']}'
            : '$base/t/${json['entryId']}/-/comment/${json['commentId']}';
      } else if (json['entryId'] != null) {
        json['apId'] = '$base/t/${json['entryId']}';
      } else if (json['postId'] != null) {
        json['apId'] = '$base/p/${json['postId']}';
      }
    }
    for (final e in json.values) {
      fillMbinApIds(e, origin);
    }
  }
}
