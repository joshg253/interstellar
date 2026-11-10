import 'package:flutter_test/flutter_test.dart';
import 'package:interstellar/src/models/comment.dart';
import 'package:interstellar/src/models/post.dart';
import 'package:interstellar/src/screens/explore/bookmark_filter.dart';

Map<String, dynamic> _base(int id, {String? title, String? body, bool? nsfw}) =>
    {
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
      'body': body,
      'lang': 'en',
      'numComments': 0,
      'comments': 0,
      'isOc': false,
      'isAdult': nsfw ?? false,
      'isPinned': false,
      'isLocked': false,
      'createdAt': '2026-01-01T00:00:00+00:00',
      'lastActive': '2026-01-01T00:00:00+00:00',
      'visibility': 'visible',
      'bookmarks': <String>[],
    };

PostModel _thread({String? title, String? body, bool nsfw = false}) =>
    PostModel.fromMbinEntry({
      ..._base(1, title: title, body: body, nsfw: nsfw),
      'entryId': 1,
    });

PostModel _post({String? body, bool nsfw = false}) =>
    PostModel.fromMbinPost({..._base(2, body: body, nsfw: nsfw), 'postId': 2});

CommentModel _comment(String body) => CommentModel.fromMbin({
  ..._base(3, body: body),
  'commentId': 3,
  'entryId': 1,
  'children': <Object?>[],
  'childCount': 0,
});

void main() {
  final thread = _thread(title: 'Cats of Rome', body: 'Some photos');
  final post = _post(body: 'Good morning');
  final comment = _comment('I agree about the cats');

  test('no filter keeps everything', () {
    const f = BookmarkFilter();
    expect(f.isActive, isFalse);
    expect([thread, post, comment].every(f.matches), isTrue);
  });

  test('kind keeps only that kind', () {
    expect(
      [
        thread,
        post,
        comment,
      ].where(const BookmarkFilter(kind: BookmarkKind.threads).matches),
      [thread],
    );
    expect(
      [
        thread,
        post,
        comment,
      ].where(const BookmarkFilter(kind: BookmarkKind.posts).matches),
      [post],
    );
    expect(
      [
        thread,
        post,
        comment,
      ].where(const BookmarkFilter(kind: BookmarkKind.comments).matches),
      [comment],
    );
  });

  test('NSFW hides or isolates flagged posts; comments carry no flag', () {
    final lewd = _thread(title: 'x', nsfw: true);
    const hide = BookmarkFilter(nsfw: BookmarkNsfw.hide);
    const only = BookmarkFilter(nsfw: BookmarkNsfw.only);
    expect([thread, lewd, comment].where(hide.matches), [thread, comment]);
    expect([thread, lewd, comment].where(only.matches), [lewd]);
  });

  test('search matches title or body, ignoring case and surrounding space', () {
    const f = BookmarkFilter(query: '  CATS ');
    expect(f.isActive, isTrue);
    expect([thread, post, comment].where(f.matches), [thread, comment]);
    expect(
      [
        thread,
        post,
        comment,
      ].where(const BookmarkFilter(query: 'morning').matches),
      [post],
    );
  });

  test('filters combine', () {
    const f = BookmarkFilter(kind: BookmarkKind.comments, query: 'cats');
    expect([thread, post, comment].where(f.matches), [comment]);
  });

  test('sort values are the ones Mbin orders bookmarks by', () {
    expect(BookmarkSort.values.map((s) => s.mbinValue), [
      'newest',
      'oldest',
      'top',
      'hot',
    ]);
  });

  test('something that is not a post or comment is never kept', () {
    expect(const BookmarkFilter().matches('a string'), isFalse);
  });
}
