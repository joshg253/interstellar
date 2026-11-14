import 'package:flutter_test/flutter_test.dart';
import 'package:interstellar/src/api/blocks.dart';

void main() {
  final site = {
    'my_user': {
      'community_blocks': [
        {
          'person': {'name': 'me'},
          'community': {
            'name': 'cats',
            'actor_id': 'https://home.example/c/cats',
          },
        },
        {
          'person': {'name': 'me'},
          'community': {
            'name': 'dogs',
            'actor_id': 'https://other.example/c/dogs',
          },
        },
      ],
      'person_blocks': [
        {
          'person': {'name': 'me'},
          'target': {'name': 'bob', 'actor_id': 'https://other.example/u/bob'},
        },
      ],
    },
  };

  test('blocked communities are named with their own host', () {
    expect(blockedFromSite(site, 'home.example', users: false), {
      'cats@home.example',
      'dogs@other.example',
    });
  });

  test('blocked users come from the person blocks', () {
    expect(blockedFromSite(site, 'home.example', users: true), {
      'bob@other.example',
    });
  });

  test('an answer without the lists is an error, not "no blocks"', () {
    expect(
      () => blockedFromSite({'my_user': null}, 'home.example', users: false),
      throwsA(isA<Exception>()),
    );
    expect(
      () => blockedFromSite({}, 'home.example', users: true),
      throwsA(isA<Exception>()),
    );
  });
}
