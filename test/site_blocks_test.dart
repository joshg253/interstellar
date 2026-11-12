import 'package:flutter_test/flutter_test.dart';
import 'package:interstellar/src/api/blocks.dart';

void main() {
  piefedTests();
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

void piefedTests() {
  test('PieFed names a person user_name, not name', () {
    final site = {
      'my_user': {
        'community_blocks': [],
        'person_blocks': [
          {
            'person': {'user_name': 'me'},
            'target': {
              'user_name': 'bob',
              'title': 'Bob',
              'actor_id': 'https://other.example/u/bob',
            },
          },
          {
            'person': {'user_name': 'me'},
            'target': {
              'user_name': 'carol@third.example',
              'actor_id': 'https://third.example/u/carol',
            },
          },
        ],
      },
    };
    expect(blockedFromSite(site, 'home.example', users: true), {
      'bob@other.example',
      'carol@third.example',
    });
  });

  test('a blocked person with no name at all is an error that says so', () {
    final site = {
      'my_user': {
        'community_blocks': [],
        'person_blocks': [
          {
            'person': {},
            'target': {'actor_id': 'https://other.example/u/x'},
          },
        ],
      },
    };
    expect(
      () => blockedFromSite(site, 'home.example', users: true),
      throwsA(
        isA<Exception>().having((e) => e.toString(), 'text', contains('name')),
      ),
    );
  });
}
