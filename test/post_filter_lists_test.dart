import 'package:flutter_test/flutter_test.dart';
import 'package:interstellar/src/controller/filter_list.dart';
import 'package:interstellar/src/models/post.dart';
import 'package:interstellar/src/screens/feed/post_filter_lists.dart';

PostModel _thread(int id, String title) => PostModel.fromMbinEntry({
  'itemType': 'entry',
  'entryId': id,
  'user': {
    'userId': 1,
    'username': 'alice',
    'createdAt': '2026-01-01T00:00:00+00:00',
    'isBot': false,
  },
  'magazine': {'magazineId': 2, 'name': 'news'},
  'domain': null,
  'title': title,
  'type': 'article',
  'image': null,
  'body': null,
  'lang': 'en',
  'numComments': 0,
  'favourites': 0,
  'dv': 0,
  'uv': 0,
  'isFavourited': false,
  'userVote': 0,
  'isOc': false,
  'isAdult': false,
  'isPinned': false,
  'isLocked': false,
  'createdAt': '2026-01-01T00:00:00+00:00',
  'lastActive': '2026-01-01T00:00:00+00:00',
  'visibility': 'visible',
  'bookmarks': <String>[],
});

FilterList _list(String phrase, {bool warn = false}) => FilterList(
  name: phrase,
  phrases: {phrase},
  matchMode: FilterListMatchMode.simple,
  caseSensitive: false,
  showWithWarning: warn,
);

void main() {
  final cats = _thread(1, 'Cats of Rome');
  final dogs = _thread(2, 'Dogs of Paris');

  test('an active list hides matching posts', () {
    final warnings = <(PostType, int), Set<String>>{};
    final shown = applyFilterLists(
      [cats, dogs],
      lists: {'a': _list('cats')},
      active: {'a': true},
      warnings: warnings,
    );
    expect(shown, [dogs]);
    expect(warnings, isEmpty);
  });

  test('a list that is not active does nothing', () {
    final shown = applyFilterLists(
      [cats, dogs],
      lists: {'a': _list('cats')},
      active: {'a': false},
      warnings: {},
    );
    expect(shown, [cats, dogs]);
  });

  test('a warning list keeps the post and names the list', () {
    final warnings = <(PostType, int), Set<String>>{};
    final shown = applyFilterLists(
      [cats, dogs],
      lists: {'a': _list('cats', warn: true)},
      active: {'a': true},
      warnings: warnings,
    );
    expect(shown, [cats, dogs]);
    expect(warnings, {
      (PostType.thread, 1): {'a'},
    });
  });
}
