import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:interstellar/src/api/client.dart';
import 'package:interstellar/src/api/feed_source.dart';
import 'package:interstellar/src/api/threads.dart';
import 'package:interstellar/src/controller/server.dart';

void main() {
  test('Lemmy post list asks for read posts too', () async {
    Uri? sent;
    final client = ServerClient(
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/post/list')) sent = request.url;
        final body = request.url.path.endsWith('/site')
            ? '{"all_languages": []}'
            : '{"posts": []}';
        return http.Response(
          body,
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
      software: ServerSoftware.lemmy,
      domain: 'example.com',
    );

    // The app's own "hide read posts" toggle decides; otherwise the account's
    // server-side setting hides read posts and the toggle can't show them.
    await APIThreads(client).list(FeedSource.community, sourceId: '5');
    expect(sent!.queryParameters['show_read'], 'true');
    expect(sent!.queryParameters['community_id'], '5');

    for (final source in [
      FeedSource.all,
      FeedSource.local,
      FeedSource.subscribed,
      FeedSource.moderated,
    ]) {
      sent = null;
      await APIThreads(client).list(source);
      expect(sent!.queryParameters['show_read'], 'true', reason: source.name);
    }
  });
}
