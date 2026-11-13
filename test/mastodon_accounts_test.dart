import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:interstellar/src/api/client.dart';
import 'package:interstellar/src/api/mastodon.dart';
import 'package:interstellar/src/controller/server.dart';

void main() {
  final accounts = [
    {'acct': 'cats@lemmy.example', 'group': true},
    {'acct': 'bob@other.example', 'group': false},
    {'acct': 'alice', 'group': false},
    {'acct': 'forum', 'group': true},
    {'acct': 'carol@third.example'},
  ];

  test('groups are the communities, everyone else is a user', () {
    expect(mastodonAccountNames(accounts, 'home.example', groups: true), {
      'cats@lemmy.example',
      'forum@home.example',
    });
    expect(mastodonAccountNames(accounts, 'home.example', groups: false), {
      'bob@other.example',
      'alice@home.example',
      'carol@third.example',
    });
  });

  group('resolving a name', () {
    MastodonAPI api(List<Map<String, Object?>> found) => MastodonAPI(
      ServerClient(
        httpClient: MockClient(
          (r) async => http.Response(jsonEncode(found), 200),
        ),
        software: ServerSoftware.mastodon,
        domain: 'home.example',
      ),
    );

    test('takes the account that was asked for', () async {
      final id = await api([
        {'id': '7', 'acct': 'Spam@bad.example'},
      ]).resolveAccount('spam@bad.example');
      expect(id, '7');
      expect(
        await api([
          {'id': '8', 'acct': 'alice'},
        ]).resolveAccount('alice@home.example'),
        '8',
      );
    });

    test('refuses a different account that the search offers instead', () {
      expect(
        () => api([
          {'id': '9', 'acct': 'spammy@friend.example'},
        ]).resolveAccount('spam@bad.example'),
        throwsException,
      );
    });
  });
}
