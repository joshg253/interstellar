import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:interstellar/src/api/client.dart';
import 'package:interstellar/src/api/moderation.dart';
import 'package:interstellar/src/controller/server.dart';

void main() {
  for (final (software, expected) in [
    (ServerSoftware.mbin, true),
    (ServerSoftware.piefed, true),
    (ServerSoftware.lemmy, false),
  ]) {
    test('${software.name} canMarkNSFW is $expected', () {
      final client = ServerClient(
        httpClient: MockClient((_) async => http.Response('{}', 200)),
        software: software,
        domain: 'example.com',
      );

      expect(APIModeration(client).canMarkNSFW, expected);
    });
  }
}
