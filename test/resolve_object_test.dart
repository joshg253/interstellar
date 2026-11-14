import 'package:flutter_test/flutter_test.dart';
import 'package:interstellar/src/api/search.dart';

void main() {
  test('a resolve_object answer becomes the lists the search parser reads', () {
    final shaped = searchShaped({
      'post': {'id': 1},
      'comment': null,
      'community': null,
      'person': {'id': 2},
    });
    expect(shaped['posts'], [
      {'id': 1},
    ]);
    expect(shaped['comments'], isEmpty);
    expect(shaped['communities'], isEmpty);
    expect(shaped['users'], [
      {'id': 2},
    ]);
    expect(shaped['next_page'], isNull);
  });

  group('sameObject', () {
    bool same(String link, String apId) => sameObject(Uri.parse(link), apId);

    test('ignores scheme, case and a trailing slash', () {
      expect(
        same('http://A.example/post/12/', 'https://a.example/post/12'),
        isTrue,
      );
    });

    test('ignores the slug Mbin adds after an id', () {
      expect(
        same(
          'https://m.example/m/cats/t/12/some-slug',
          'https://m.example/m/cats/t/12',
        ),
        isTrue,
      );
      expect(
        same(
          'https://m.example/m/cats/t/12/some-slug/-/comment/9',
          'https://m.example/m/cats/t/12/-/comment/9',
        ),
        isTrue,
      );
    });

    test('tells other posts, other comments and other servers apart', () {
      expect(
        same(
          'https://m.example/m/cats/t/12/x',
          'https://m.example/m/cats/t/13',
        ),
        isFalse,
      );
      expect(
        same(
          'https://m.example/m/cats/t/12/x/-/comment/9',
          'https://m.example/m/cats/t/12',
        ),
        isFalse,
      );
      expect(
        same('https://m.example/post/1', 'https://n.example/post/1'),
        isFalse,
      );
    });
  });
}
