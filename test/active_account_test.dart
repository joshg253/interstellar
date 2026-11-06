import 'package:flutter_test/flutter_test.dart';
import 'package:interstellar/src/screens/feed/merged_comment_section.dart';

void main() {
  const accounts = ['a@fedia.test', 'b@piefed.test', 'c@lemmy.test'];
  bool signedIn(String a) => a != 'c@lemmy.test';

  test('an explicit pick wins', () {
    expect(
      pickActiveAccount(
        chosen: 'a@fedia.test',
        selected: 'b@piefed.test',
        accounts: accounts,
        signedIn: signedIn,
      ),
      'a@fedia.test',
    );
  });

  test('with no pick, the account you are on is used', () {
    expect(
      pickActiveAccount(
        chosen: null,
        selected: 'b@piefed.test',
        accounts: accounts,
        signedIn: signedIn,
      ),
      'b@piefed.test',
    );
  });

  test(
    'a selected account that cannot act falls back to the first that can',
    () {
      expect(
        pickActiveAccount(
          chosen: null,
          selected: 'c@lemmy.test',
          accounts: accounts,
          signedIn: signedIn,
        ),
        'a@fedia.test',
      );
    },
  );

  test('a pick outside the list is ignored', () {
    expect(
      pickActiveAccount(
        chosen: 'z@gone.test',
        selected: 'b@piefed.test',
        accounts: accounts,
        signedIn: signedIn,
      ),
      'b@piefed.test',
    );
  });

  test('nobody can act', () {
    expect(
      pickActiveAccount(
        chosen: null,
        selected: 'c@lemmy.test',
        accounts: ['c@lemmy.test'],
        signedIn: signedIn,
      ),
      isNull,
    );
  });
}
