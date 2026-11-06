import 'package:flutter_test/flutter_test.dart';
import 'package:interstellar/src/utils/models.dart';

void main() {
  const origin = 'https://mbin.example';

  test('a comment in a remote magazine gets the id other servers use', () {
    final json = {
      'commentId': 9001,
      'entryId': 4001,
      'apId': null,
      'magazine': {
        'magazineId': 3,
        'name': 'funny@lemmy.example',
        'apProfileId': 'https://lemmy.example/c/funny',
      },
    };
    fillMbinApIds(json, origin);
    expect(
      json['apId'],
      'https://mbin.example/m/funny@lemmy.example/t/4001/-/comment/9001',
    );
  });

  test('a thread in a local magazine', () {
    final json = {
      'entryId': 4002,
      'apId': null,
      'magazine': {'magazineId': 1, 'name': 'news'},
    };
    fillMbinApIds(json, origin);
    expect(json['apId'], 'https://mbin.example/m/news/t/4002');
  });

  test('a microblog post and its reply', () {
    final json = {
      'postId': 4003,
      'apId': null,
      'magazine': {'magazineId': 2, 'name': 'random'},
    };
    final reply = {
      'commentId': 7,
      'postId': 4003,
      'apId': null,
      'magazine': {'magazineId': 2, 'name': 'random'},
    };
    fillMbinApIds(json, origin);
    fillMbinApIds(reply, origin);
    expect(json['apId'], 'https://mbin.example/m/random/p/4003');
    expect(reply['apId'], 'https://mbin.example/m/random/p/4003/-/reply/7');
  });

  test('walks lists and nested replies', () {
    final json = {
      'items': [
        {
          'commentId': 1,
          'entryId': 9,
          'apId': null,
          'magazine': {'magazineId': 1, 'name': 'm'},
          'children': [
            {
              'commentId': 2,
              'entryId': 9,
              'apId': null,
              'magazine': {'magazineId': 1, 'name': 'm'},
              'children': <dynamic>[],
            },
          ],
        },
      ],
    };
    fillMbinApIds(json, origin);
    final top = (json['items']! as List).single as Map<String, dynamic>;
    final child = (top['children'] as List).single as Map<String, dynamic>;
    expect(top['apId'], 'https://mbin.example/m/m/t/9/-/comment/1');
    expect(child['apId'], 'https://mbin.example/m/m/t/9/-/comment/2');
  });

  test('keeps an id the server gave and leaves other software alone', () {
    final given = {
      'entryId': 1,
      'apId': 'https://lemmy.example/post/5',
      'magazine': {'magazineId': 1, 'name': 'm'},
    };
    final lemmy = {
      'post': {'id': 1, 'ap_id': 'https://x.example/post/1'},
      'community': {'id': 2, 'name': 'c'},
    };
    fillMbinApIds(given, origin);
    fillMbinApIds(lemmy, origin);
    expect(given['apId'], 'https://lemmy.example/post/5');
    expect(lemmy.containsKey('apId'), isFalse);
  });
}
