import 'package:flutter_test/flutter_test.dart';
import 'package:interstellar/src/models/community.dart';
import 'package:interstellar/src/models/post.dart';
import 'package:interstellar/src/screens/explore/community_mod_panel.dart';

Map<String, Object?> _person(int id) => {
  'id': id,
  'user_name': 'user$id',
  'local': true,
  'bot': false,
  'published': '2025-01-01T00:00:00Z',
  'actor_id': 'https://example.com/u/user$id',
};

CommunityReportModel _report({bool removed = false}) =>
    CommunityReportModel.fromPiefed(
      {
        'post_report': {
          'id': 5,
          'creator_id': 2,
          'post_id': 11,
          'reason': 'spam',
          'resolved': false,
          'published': '2025-01-02T00:00:00Z',
        },
        'post': {
          'id': 11,
          'title': 'A post',
          'body': 'text',
          'published': '2025-01-01T00:00:00Z',
          'language_id': 0,
          'nsfw': false,
          'sticky': false,
          'locked': false,
          'removed': removed,
          'deleted': false,
          'ap_id': 'https://example.com/post/11',
        },
        'community': {
          'id': 7,
          'name': 'test',
          'title': 'Test',
          'local': true,
          'nsfw': false,
          'restricted_to_mods': false,
          'actor_id': 'https://example.com/c/test',
        },
        'counts': {
          'comments': 0,
          'upvotes': 1,
          'downvotes': 0,
          'newest_comment_time': '2025-01-01T00:00:00Z',
        },
        'creator': _person(2),
        'post_creator': _person(3),
        'saved': false,
      },
      langCodeIdPairs: [('und', 0)],
    );

void main() {
  test('a removed or deleted post counts as deleted', () {
    expect(postIsDeleted(PostVisibility.trashed), isTrue);
    expect(postIsDeleted(PostVisibility.soft_deleted), isTrue);
    expect(postIsDeleted(PostVisibility.visible), isFalse);
    expect(postIsDeleted(null), isFalse);
  });

  test('the report keeps the deleted state it was last given', () {
    final report = _report();
    expect(postIsDeleted(report.subjectPost?.visibility), isFalse);

    final removed = withSubjectDeleted(report, deleted: true);
    expect(postIsDeleted(removed.subjectPost?.visibility), isTrue);

    final restored = withSubjectDeleted(removed, deleted: false);
    expect(postIsDeleted(restored.subjectPost?.visibility), isFalse);
  });

  test('a report without a post is left alone', () {
    final report = _report().copyWith(subjectPost: null);
    expect(withSubjectDeleted(report, deleted: true), report);
  });
}
