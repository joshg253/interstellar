import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:interstellar/src/api/host_check.dart';

void main() {
  Future<({HostFailure kind, String detail})?> probe(
    Future<http.Response> Function(http.Request) handler,
  ) => probeHost('example.com', client: MockClient(handler));

  test('a server with a nodeinfo document passes', () async {
    expect(
      await probe((_) async => http.Response('{"links": []}', 200)),
      isNull,
    );
  });

  test('an error status is an http failure with the status', () async {
    final r = await probe((_) async => http.Response('', 403));
    expect(r?.kind, HostFailure.http);
    expect(r?.detail, 'HTTP 403');
  });

  test('a page that is not nodeinfo is not a fediverse server', () async {
    final r = await probe((_) async => http.Response('<html></html>', 200));
    expect(r?.kind, HostFailure.notFediverse);
  });

  test('no connection is a network failure', () async {
    final r = await probe(
      (_) async => throw const SocketException('Failed host lookup'),
    );
    expect(r?.kind, HostFailure.network);
    expect(r?.detail, 'Failed host lookup');
  });
}
