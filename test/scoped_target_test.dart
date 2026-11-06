import 'package:flutter_test/flutter_test.dart';
import 'package:interstellar/src/widgets/account_scope.dart';

void main() {
  test('outside a scope nothing changes', () {
    expect(
      scopedTarget('lemmyshitpost', 381, scopeHost: null, viewerHost: 'a.test'),
      (name: 'lemmyshitpost', id: 381),
    );
  });

  test('same server keeps the id', () {
    expect(
      scopedTarget(
        'lemmyshitpost',
        381,
        scopeHost: 'a.test',
        viewerHost: 'a.test',
      ),
      (name: 'lemmyshitpost', id: 381),
    );
  });

  test('another server drops the id and qualifies a bare name', () {
    expect(scopedTarget('mine', 5, scopeHost: 'b.test', viewerHost: 'a.test'), (
      name: 'mine@b.test',
      id: null,
    ));
  });

  test('another server keeps a qualified name', () {
    expect(
      scopedTarget(
        'lemmyshitpost@lemmy.world',
        381,
        scopeHost: 'b.test',
        viewerHost: 'a.test',
      ),
      (name: 'lemmyshitpost@lemmy.world', id: null),
    );
  });

  test('a name qualified with the viewing server becomes bare there', () {
    expect(
      scopedTarget('x@a.test', 9, scopeHost: 'b.test', viewerHost: 'a.test'),
      (name: 'x', id: null),
    );
  });
}
