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

void main() {
  test('reads the software name from /nodeinfo/2.0.json', () async {
    final client = MockClient((req) async => _json(_info('mbin')));
    expect(
      await getServerSoftware('example.com', client: client),
      ServerSoftware.mbin,
    );
  });

  test(
    'falls back to well-known discovery when 2.0.json is not JSON',
    () async {
      final client = MockClient((req) async {
        switch (req.url.path) {
          case '/nodeinfo/2.0.json':
            return _html();
          case '/.well-known/nodeinfo':
            return _json({
              'links': [
                {
                  'rel': 'http://nodeinfo.diaspora.software/ns/schema/2.1',
                  'href': 'https://example.com/nodeinfo/2.1',
                },
              ],
            });
          case '/nodeinfo/2.1':
            return _json(_info('catodon'));
        }
        return http.Response('', 404);
      });
      expect(
        await getServerSoftware('example.com', client: client),
        ServerSoftware.mastodon,
      );
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
