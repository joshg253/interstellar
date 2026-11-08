import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:interstellar/src/api/client.dart';
import 'package:interstellar/src/api/threads.dart';
import 'package:interstellar/src/controller/server.dart';

void main() {
  for (final (software, titleKey, otherKey) in [
    (ServerSoftware.lemmy, 'name', 'title'),
    (ServerSoftware.piefed, 'title', 'name'),
  ]) {
    test('$software post edit sends the title as $titleKey', () async {
      http.Request? sent;
      final client = ServerClient(
        httpClient: MockClient((request) async {
          if (request.method == 'PUT') sent = request;
          // Stop after the request; the response shape is not under test.
          return http.Response('{}', 200);
        }),
        software: software,
        domain: 'example.com',
      );

      try {
        await APIThreads(client).edit(5, 'Title', false, 'Body', 'en', false);
      } catch (_) {}

      expect(sent!.url.path, endsWith('/post'));
      final body = jsonDecode(sent!.body) as Map<String, dynamic>;
      expect(body, containsPair(titleKey, 'Title'));
      expect(body, isNot(contains(otherKey)));
    });
  }
}
