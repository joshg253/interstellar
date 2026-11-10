import 'package:flutter_test/flutter_test.dart';
import 'package:interstellar/src/screens/feed/merged_comment_section.dart';

void main() {
  const accounts = ['a@a.test', 'b@b.test', 'c@c.test'];
  bool signedIn(String a) => a != 'c@c.test';

  test('an explicit pick wins', () {
    expect(
      pickActiveAccount(
        chosen: 'a@a.test',
        selected: 'b@b.test',
        accounts: accounts,
        signedIn: signedIn,
      ),
      'a@a.test',
    );
  });

  test('with no pick, the account you are on is used', () {
    expect(
      pickActiveAccount(
        chosen: null,
        selected: 'b@b.test',
        accounts: accounts,
        signedIn: signedIn,
      ),
      'b@b.test',
    );
  });

  test(
    'a selected account that cannot act falls back to the first that can',
    () {
      expect(
        pickActiveAccount(
          chosen: null,
          selected: 'c@c.test',
          accounts: accounts,
          signedIn: signedIn,
        ),
        'a@a.test',
      );
    },
  );

  test('a pick outside the list is ignored', () {
    expect(
      pickActiveAccount(
        chosen: 'z@gone.test',
        selected: 'b@b.test',
        accounts: accounts,
        signedIn: signedIn,
      ),
      'b@b.test',
    );
  });

  test('nobody can act', () {
    expect(
      pickActiveAccount(
        chosen: null,
        selected: 'c@c.test',
        accounts: ['c@c.test'],
        signedIn: signedIn,
      ),
      isNull,
    );
  });

  group('a group without the chosen account', () {
    test('is read-only when the pick has no copy there', () {
      expect(
        chosenAccountMissing('a@a.test', ['b@b.test', 'c@c.test']),
        isTrue,
      );
    });

    test('is not when the pick has a copy', () {
      expect(chosenAccountMissing('b@b.test', ['b@b.test']), isFalse);
    });

    test('is not when nothing was picked', () {
      expect(chosenAccountMissing(null, ['b@b.test']), isFalse);
    });
  });
}
