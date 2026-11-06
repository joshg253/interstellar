import 'package:flutter_test/flutter_test.dart';
import 'package:interstellar/src/models/post.dart';
import 'package:interstellar/src/screens/feed/merged_comment_section.dart';
import 'package:interstellar/src/screens/feed/merged_comments.dart';

PostModel _post(int id, String apId) => PostModel.fromMbinEntry({
  'entryId': id,
  'apId': apId,
  'user': {
    'userId': 3,
    'username': 'someone',
    'isBot': false,
    'createdAt': '2024-01-01T00:00:00+00:00',
  },
  'magazine': {'magazineId': 9, 'name': 'test'},
  'title': 't',
  'lang': 'en',
  'numComments': 1,
  'isOc': false,
  'isAdult': false,
  'isPinned': false,
  'isLocked': false,
  'createdAt': '2026-11-06T00:00:00+00:00',
  'lastActive': '2026-11-06T00:00:00+00:00',
  'visibility': 'visible',
});

void main() {
  test('different cross-post groups get different keys', () {
    final a = MergedNode<PostModel>([
      ('x@a.test', _post(1, 'https://a/1')),
    ], []);
    final b = MergedNode<PostModel>([
      ('x@a.test', _post(2, 'https://a/2')),
    ], []);

    expect(crossPostGroupKey(a, 1), isNot(crossPostGroupKey(b, 1)));
  });

  test('the same group keeps its key, and changes when copies change', () {
    final a = MergedNode<PostModel>([
      ('x@a.test', _post(1, 'https://a/1')),
    ], []);

    expect(crossPostGroupKey(a, 1), crossPostGroupKey(a, 1));
    expect(crossPostGroupKey(a, 1), isNot(crossPostGroupKey(a, 2)));
  });
}
