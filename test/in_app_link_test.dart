import 'package:flutter_test/flutter_test.dart';
import 'package:interstellar/src/models/post.dart';
import 'package:interstellar/src/utils/in_app_link.dart';

InAppLink? _p(String url, {String own = 'home.example'}) =>
    parseInAppLink(Uri.parse(url), ownHost: own);

void main() {
  group('communities and users', () {
    test("a community on the account's own server keeps a bare name", () {
      for (final u in [
        'https://home.example/c/cats',
        'https://home.example/m/cats',
        'https://home.example/c/cats/',
      ]) {
        expect(
          _p(u),
          isA<CommunityLink>().having((l) => l.name, 'name', 'cats'),
        );
      }
    });

    test('a community elsewhere is qualified with its host', () {
      expect(
        _p('https://other.example/c/cats'),
        isA<CommunityLink>().having(
          (l) => l.name,
          'name',
          'cats@other.example',
        ),
      );
    });

    test('a name that already has a host keeps it, or drops the own host', () {
      expect(
        _p('https://home.example/c/cats@other.example'),
        isA<CommunityLink>().having(
          (l) => l.name,
          'name',
          'cats@other.example',
        ),
      );
      expect(
        _p('https://other.example/c/cats@home.example'),
        isA<CommunityLink>().having((l) => l.name, 'name', 'cats'),
      );
    });

    test('users, with or without a leading @', () {
      expect(
        _p('https://other.example/u/bob'),
        isA<UserLink>().having((l) => l.name, 'name', 'bob@other.example'),
      );
      expect(
        _p('https://home.example/u/@bob'),
        isA<UserLink>().having((l) => l.name, 'name', 'bob'),
      );
    });
  });

  group('posts and comments', () {
    test("only the account's own server can open them by id", () {
      expect(_p('https://other.example/post/12'), isNull);
      expect(_p('https://other.example/comment/12'), isNull);
      expect(_p('https://other.example/m/cats/t/12/slug'), isNull);
    });

    test('Lemmy and PieFed paths', () {
      expect(
        _p('https://home.example/post/12'),
        isA<PostLink>()
            .having((l) => l.id, 'id', 12)
            .having((l) => l.type, 'type', PostType.thread),
      );
      expect(
        _p('https://home.example/comment/34'),
        isA<CommentLink>()
            .having((l) => l.id, 'id', 34)
            .having((l) => l.type, 'type', PostType.thread),
      );
    });

    test('Mbin thread, microblog and comment paths', () {
      expect(
        _p('https://home.example/m/cats/t/12/some-slug'),
        isA<PostLink>()
            .having((l) => l.id, 'id', 12)
            .having((l) => l.type, 'type', PostType.thread),
      );
      expect(
        _p('https://home.example/m/cats/p/13'),
        isA<PostLink>()
            .having((l) => l.id, 'id', 13)
            .having((l) => l.type, 'type', PostType.microblog),
      );
      expect(
        _p('https://home.example/m/cats/t/12/-/comment/99'),
        isA<CommentLink>()
            .having((l) => l.id, 'id', 99)
            .having((l) => l.type, 'type', PostType.thread),
      );
    });
  });

  test('other shapes, schemes and bad ids are not handled', () {
    for (final u in [
      'https://home.example/',
      'https://home.example/about',
      'https://home.example/c/',
      'https://home.example/post/abc',
      'https://home.example/post/99999999999999999999',
      'https://home.example/@bob',
      'ftp://home.example/c/cats',
      'javascript:alert(1)',
      'https://home.example/c/cats%20dogs',
    ]) {
      expect(_p(u), isNull, reason: u);
    }
  });
}
