import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:interstellar/src/api/client.dart';
import 'package:interstellar/src/api/threads.dart';
import 'package:interstellar/src/controller/server.dart';
import 'package:interstellar/src/models/post.dart';

Map<String, Object?> _entry({List<String>? tags}) => {
  'entryId': 4,
  'title': 'T',
  'body': 'b',
  'tags': ?tags,
  'user': {
    'userId': 1,
    'username': 'u',
    'isBot': false,
    'createdAt': '2025-01-01T00:00:00+00:00',
    'apId': null,
  },
  'magazine': {'magazineId': 2, 'name': 'm'},
  'image': null,
  'domain': null,
  'url': null,
  'lang': 'en',
  'numComments': 0,
  'uv': 0,
  'dv': 0,
  'favourites': 0,
  'isOc': false,
  'isAdult': false,
  'isPinned': false,
  'isLocked': false,
  'createdAt': '2025-01-01T00:00:00+00:00',
  'editedAt': null,
  'lastActive': '2025-01-01T00:00:00+00:00',
  'visibility': 'visible',
};

void main() {
  test('hashtags the body carries are not sent back as tags', () {
    expect(mbinExplicitTags(['foo', 'Bar', 'extra'], 'text #FOO and #bar'), [
      'extra',
    ]);
    expect(mbinExplicitTags(['a'], null), ['a']);
    // Mbin's own rule: Unicode letters, at least two characters, not mid-word.
    expect(
      mbinExplicitTags(['café', 'foo', 'ab', 'x'], '#café #foo-bar word#ab #x'),
      ['ab', 'x'],
    );
  });

  test('Mbin entries keep their tags', () {
    expect(PostModel.fromMbinEntry(_entry(tags: ['a', 'b'])).tags, ['a', 'b']);
    expect(PostModel.fromMbinEntry(_entry()).tags, isEmpty);
  });

  test('Mbin post edit sends the tags it was given', () async {
    http.Request? sent;
    final client = ServerClient(
      httpClient: MockClient((request) async {
        sent = request;
        return http.Response(jsonEncode(_entry(tags: ['a', 'b'])), 200);
      }),
      software: ServerSoftware.mbin,
      domain: 'example.com',
    );

    await APIThreads(
      client,
    ).edit(4, 'T', false, 'b', 'en', false, tags: ['a', 'b']);

    expect(jsonDecode(sent!.body), containsPair('tags', ['a', 'b']));
  });
}
