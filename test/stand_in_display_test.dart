import 'package:flutter_test/flutter_test.dart';
import 'package:interstellar/src/models/post.dart';
import 'package:interstellar/src/screens/feed/cross_account_feed_screen.dart';

PostModel _post() => PostModel.fromMbinPost({
  'postId': 4,
  'body': 'b',
  'bookmarks': [''],
  'userVote': 1,
  'isFavourited': true,
  'user': {
    'userId': 1,
    'username': 'u',
    'isBot': false,
    'createdAt': '2025-01-01T00:00:00+00:00',
    'apId': null,
  },
  'magazine': {'magazineId': 2, 'name': 'm'},
  'image': null,
  'lang': 'en',
  'comments': 0,
  'uv': 0,
  'dv': 0,
  'favourites': 0,
  'isAdult': false,
  'isPinned': false,
  'isLocked': false,
  'createdAt': '2025-01-01T00:00:00+00:00',
  'editedAt': null,
  'lastActive': '2025-01-01T00:00:00+00:00',
  'visibility': 'visible',
});

void main() {
  test('a copy shown for another account keeps its bookmark state', () {
    final post = _post();
    expect(post.myVote, 1);
    final shown = withoutActorVotes(post);
    expect(shown.myVote, isNull);
    expect(shown.myBoost, isNull);
    // actions run as the shown account, so its bookmark state is the right one
    expect(shown.bookmarks, ['']);
  });
}
