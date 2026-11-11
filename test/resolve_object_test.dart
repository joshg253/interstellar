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
}
