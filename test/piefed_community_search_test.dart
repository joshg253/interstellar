import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:interstellar/src/api/client.dart';
import 'package:interstellar/src/api/community.dart';
import 'package:interstellar/src/controller/server.dart';

Future<String?> _nextPage(
  Map<String, Object?> extra, {
  String? page,
  int count = 1,
}) async {
  final client = ServerClient(
    httpClient: MockClient(
      (_) async => http.Response(
        jsonEncode({
          'communities': [
            for (var i = 0; i < count; i++)
              {
                'community': {
                  'id': 1,
                  'name': 'c',
                  'title': 'C',
                  'nsfw': false,
                  'local': true,
                  'actor_id': 'https://example.com/c/c',
                  'restricted_to_mods': false,
                },
                'subscribed': 'NotSubscribed',
                'counts': {
                  'subscriptions_count': 0,
                  'post_count': 0,
                  'post_reply_count': 0,
                },
              },
          ],
          ...extra,
        }),
        200,
        headers: {'content-type': 'application/json'},
      ),
    ),
    software: ServerSoftware.piefed,
    domain: 'example.com',
  );

  return (await APICommunity(client).list(search: 'c', page: page)).nextPage;
}

void main() {
  group('PieFed community search', () {
    test('goes on to the next page when the server gives none', () async {
      expect(await _nextPage({}), '2');
    });

    test('stops when a page comes back empty', () async {
      expect(await _nextPage({}, count: 0), isNull);
    });
    test('counts on from the page it asked for', () async {
      expect(await _nextPage({}, page: '2'), '3');
    });
    test('trusts a next page the server does give', () async {
      expect(await _nextPage({'next_page': '7'}), '7');
      expect(await _nextPage({'next_page': null}), isNull);
    });
  });
}
