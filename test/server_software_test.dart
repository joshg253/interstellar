import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:interstellar/src/api/api.dart';
import 'package:interstellar/src/controller/server.dart';

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json'},
);

http.Response _html() => http.Response('<!DOCTYPE html><html></html>', 200);

Map<String, dynamic> _info(String name) => {
  'software': {'name': name},
};

Map<String, dynamic> _links(List<String> hrefs) => {
  'links': [
    for (final href in hrefs)
      {'rel': 'http://nodeinfo.diaspora.software/ns/schema/2.1', 'href': href},
  ],
};

/// Answers only the exact URLs in [routes] and gives any other request a 404.
MockClient _client(
  Map<String, http.Response Function()> routes, {
  List<String>? seen,
}) => MockClient((req) async {
  seen?.add(req.url.toString());
  final route = routes[req.url.toString()];
  if (route == null) return http.Response('', 404);
  return route();
});

void main() {
  test('reads the software name from /nodeinfo/2.0.json', () async {
    final seen = <String>[];
    final client = _client({
      'https://example.com/nodeinfo/2.0.json': () => _json(_info('piefed')),
    }, seen: seen);
    expect(
      await getServerSoftware('example.com', client: client),
      ServerSoftware.piefed,
    );
    expect(seen, ['https://example.com/nodeinfo/2.0.json']);
  });

  test('each known name maps to its software', () async {
    for (final (name, software) in [
      ('mbin', ServerSoftware.mbin),
      ('lemmy', ServerSoftware.lemmy),
      ('piefed', ServerSoftware.piefed),
      ('mastodon', ServerSoftware.mastodon),
      ('catodon', ServerSoftware.mastodon),
    ]) {
      final client = _client({
        'https://example.com/nodeinfo/2.0.json': () => _json(_info(name)),
      });
      expect(
        await getServerSoftware('example.com', client: client),
        software,
        reason: name,
      );
    }
  });

  test(
    'falls back to well-known discovery when 2.0.json is not JSON',
    () async {
      final client = _client({
        'https://example.com/nodeinfo/2.0.json': _html,
        'https://example.com/.well-known/nodeinfo': () =>
            _json(_links(['https://example.com/nodeinfo/2.1'])),
        'https://example.com/nodeinfo/2.1': () => _json(_info('catodon')),
      });
      expect(
        await getServerSoftware('example.com', client: client),
        ServerSoftware.mastodon,
      );
    },
  );

  test(
    'a link that fails does not stop the next one from being tried',
    () async {
      final client = MockClient((req) async {
        switch (req.url.toString()) {
          case 'https://example.com/nodeinfo/2.0.json':
            return _html();
          case 'https://example.com/.well-known/nodeinfo':
            return _json(
              _links([
                'https://example.com/nodeinfo/2.1',
                'https://example.com/other/nodeinfo',
              ]),
            );
          case 'https://example.com/other/nodeinfo':
            throw http.ClientException('reset');
          case 'https://example.com/nodeinfo/2.1':
            return _json(_info('lemmy'));
        }
        return http.Response('', 404);
      });
      expect(
        await getServerSoftware('example.com', client: client),
        ServerSoftware.lemmy,
      );
    },
  );

  test(
    'links to another host or a plain-http URL are never requested',
    () async {
      final seen = <String>[];
      final client = _client({
        'https://example.com/nodeinfo/2.0.json': _html,
        'https://example.com/.well-known/nodeinfo': () => _json(
          _links([
            'https://attacker.example/nodeinfo/2.1',
            'http://example.com/nodeinfo/2.1',
            'https://192.168.1.1/nodeinfo/2.1',
          ]),
        ),
      }, seen: seen);
      expect(await getServerSoftware('example.com', client: client), isNull);
      expect(seen, [
        'https://example.com/nodeinfo/2.0.json',
        'https://example.com/.well-known/nodeinfo',
      ]);
    },
  );

  test('returns null when nothing usable is served', () async {
    final client = MockClient((req) async => _html());
    expect(await getServerSoftware('example.com', client: client), isNull);
  });

  test('returns null when the server is unreachable', () async {
    final client = MockClient(
      (req) async => throw http.ClientException('no route'),
    );
    expect(await getServerSoftware('example.com', client: client), isNull);
  });
}
