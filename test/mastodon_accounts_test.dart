import 'package:flutter_test/flutter_test.dart';
import 'package:interstellar/src/api/mastodon.dart';

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
}
