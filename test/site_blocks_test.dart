import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:interstellar/src/api/api.dart';
import 'package:interstellar/src/api/blocks.dart';
import 'package:interstellar/src/api/client.dart';
import 'package:interstellar/src/controller/server.dart';

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

  group('Mbin blocked lists', () {
    API mbin(int Function() count) => API(
      ServerClient(
        httpClient: MockClient((r) async {
          count();
          return http.Response(
            jsonEncode({
              'items': <Object?>[],
              'pagination': {'currentPage': 1, 'maxPage': 1000000},
            }),
            200,
          );
        }),
        software: ServerSoftware.mbin,
        domain: 'home.example',
      ),
    );

    test('a server that never ends its pages is stopped with an error', () {
      var asked = 0;
      expect(
        listBlocked(mbin(() => ++asked), 'home.example', users: true),
        throwsException,
      );
      expect(asked, lessThanOrEqualTo(101));
    });

    test('Cancel ends the paging', () async {
      var asked = 0;
      final names = await listBlocked(
        mbin(() => ++asked),
        'home.example',
        users: true,
        cancelled: () => asked >= 2,
      );
      expect(names, isEmpty);
      expect(asked, 2);
    });
  });
}
