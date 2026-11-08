import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:interstellar/src/api/client.dart';
import 'package:interstellar/src/api/community_moderation.dart';
import 'package:interstellar/src/controller/server.dart';

void main() {
  test('piefed remove icon names the community', () async {
    http.Request? sent;
    final client = ServerClient(
      httpClient: MockClient((request) async {
        sent = request;
        return http.Response('{}', 200);
      }),
      software: ServerSoftware.piefed,
      domain: 'example.com',
    );

    await APICommunityModeration(client).removeIcon(7);

    expect(sent!.method, 'PUT');
    expect(jsonDecode(sent!.body), {'community_id': 7, 'icon_url': ''});
  });
}
