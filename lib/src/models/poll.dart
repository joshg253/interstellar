import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:interstellar/src/utils/models.dart';
import 'package:interstellar/src/utils/utils.dart';

part 'poll.freezed.dart';

@freezed
abstract class PollChoiceModel with _$PollChoiceModel {
  const factory PollChoiceModel({
    required int id,
    required String text,
    required int sortOrder,
    required int numVotes,
    required bool chosen,
  }) = _PollChoiceModel;
}

@freezed
abstract class PollModel with _$PollModel {
  const factory PollModel({
    required int postId,
    required DateTime endPoll,
    required bool multiple,
    required bool localOnly,
    required List<PollChoiceModel> choices,
  }) = _PollModel;

  const PollModel._();

  /// A Mastodon poll. Its options have no ids, so a choice id is its index.
  /// A poll that never expires gets a far-off end.
  factory PollModel.fromMastodon(int postId, JsonMap json) {
    final own = (json['own_votes'] as List<dynamic>? ?? []).cast<int>();
    final options = (json['options']! as List<dynamic>).cast<JsonMap>();

    return PollModel(
      postId: postId,
      endPoll:
          optionalDateTime(json['expires_at'] as String?)?.toLocal() ??
          DateTime.utc(9999),
      multiple: (json['multiple'] as bool?) ?? false,
      localOnly: false,
      choices: [
        for (final (i, option) in options.indexed)
          PollChoiceModel(
            id: i,
            text: option['title']! as String,
            sortOrder: i,
            // hidden until the poll closes
            numVotes: (option['votes_count'] as int?) ?? 0,
            chosen: own.contains(i),
          ),
      ],
    );
  }

  factory PollModel.fromPiefed(int postId, JsonMap json) {
    final choices = json['choices']! as List<dynamic>;
    final votes = json['my_votes'] as List<dynamic>? ?? [];

    return PollModel(
      postId: postId,
      endPoll: DateTime.parse(json['end_poll']! as String).toLocal(),
      multiple: (json['mode']! as String) == 'multiple',
      localOnly: json['local_only']! as bool,
      choices: choices
          .map(
            (choice) => PollChoiceModel(
              id: choice['id'],
              text: choice['choice_text'],
              sortOrder: choice['sort_order'],
              numVotes: choice['num_votes'],
              chosen: votes.contains(choice['id'] as int),
            ),
          )
          .toList(),
    );
  }

  /// A poll with no end date (some servers allow it) carries a far-off end.
  bool get neverEnds => endPoll.year >= 9999;
}
