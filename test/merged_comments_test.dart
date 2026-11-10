import 'package:flutter_test/flutter_test.dart';
import 'package:interstellar/src/screens/feed/merged_comments.dart';

// (key, children) stands in for a comment
typedef C = (String?, List<dynamic>);

void main() {
  pickTests();
  List<MergedNode<C>> merge(List<(String, List<C>)> lists) => mergeTrees<C>(
    lists,
    keyOf: (c) => c.$1,
    childrenOf: (c) => c.$2.cast<C>(),
  );

  test('same key across accounts becomes one node with a copy each', () {
    final nodes = merge([
      ('a', [('x', <C>[]), ('y', <C>[])]),
      ('b', [('y', <C>[]), ('z', <C>[])]),
    ]);
    expect(nodes.map((n) => n.copies.map((c) => c.$1).toList()), [
      ['a'],
      ['a', 'b'],
      ['b'],
    ]);
    expect(nodes.map((n) => n.copies.first.$2.$1), ['x', 'y', 'z']);
  });

  test(
    'children merge recursively, including ones only some accounts have',
    () {
      final nodes = merge([
        (
          'a',
          [
            ('p', [('r1', <C>[])]),
          ],
        ),
        (
          'b',
          [
            ('p', [('r1', <C>[]), ('r2', <C>[])]),
          ],
        ),
      ]);
      expect(nodes, hasLength(1));
      final kids = nodes.single.children;
      expect(kids.map((k) => k.copies.first.$2.$1), ['r1', 'r2']);
      expect(kids[0].copies.map((c) => c.$1), ['a', 'b']);
      expect(kids[1].copies.map((c) => c.$1), ['b']);
    },
  );

  test('null keys are never merged', () {
    final nodes = merge([
      ('a', [(null, <C>[])]),
      ('b', [(null, <C>[])]),
    ]);
    expect(nodes, hasLength(2));
  });

  test('a repeated key within one account is not duplicated', () {
    final nodes = merge([
      ('a', [('x', <C>[]), ('x', <C>[])]),
    ]);
    expect(nodes.single.copies, hasLength(1));
  });
}

void pickTests() {
  group('pickCopy', () {
    final copies = [('a', 1), ('b', 2), ('c', 3)];

    test('prefers the active account', () {
      expect(pickCopy(copies, 'b'), ('b', 2));
    });

    test('falls back to the first copy when the active account lacks it', () {
      expect(pickCopy(copies, 'z'), ('a', 1));
      expect(pickCopy(copies, null), ('a', 1));
    });
  });
}
