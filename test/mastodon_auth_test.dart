import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:interstellar/src/api/mastodon_auth.dart';

void main() {
  final redirect = Uri.parse('interstellar://auth');

  test('registers an app and returns its credentials', () async {
    late http.Request seen;
    final auth = MastodonAuth(
      MockClient((request) async {
        seen = request;
        return http.Response(
          jsonEncode({'client_id': 'cid', 'client_secret': 'sec'}),
          200,
        );
      }),
      'example.social',
      redirect,
    );

    final app = await auth.registerApp();

    expect(seen.url.toString(), 'https://example.social/api/v1/apps');
    final body = jsonDecode(seen.body) as Map<String, dynamic>;
    expect(body['redirect_uris'], 'interstellar://auth');
    expect(body['scopes'], 'read write follow');
    expect(app.clientId, 'cid');
    expect(app.clientSecret, 'sec');
  });

  test('builds an authorize URL with a PKCE challenge', () {
    final auth = MastodonAuth(
      MockClient((_) async => http.Response('{}', 200)),
      'example.social',
      redirect,
    );
    final session = auth.authorization(
      const MastodonApp(clientId: 'cid', clientSecret: 'sec'),
    );

    final q = session.url.queryParameters;
    expect(session.url.host, 'example.social');
    expect(session.url.path, '/oauth/authorize');
    expect(q['response_type'], 'code');
    expect(q['client_id'], 'cid');
    expect(q['redirect_uri'], 'interstellar://auth');
    expect(q['scope'], 'read write follow');
    expect(q['code_challenge_method'], 'S256');
    expect(
      q['code_challenge'],
      base64UrlEncode(
        sha256.convert(ascii.encode(session.codeVerifier)).bytes,
      ).replaceAll('=', ''),
    );
    expect(q['state'], session.state);
    expect(session.state, isNotEmpty);
    expect(session.codeVerifier.length, greaterThanOrEqualTo(43));
  });

  test('exchanges the code for an access token', () async {
    late http.Request seen;
    final auth = MastodonAuth(
      MockClient((request) async {
        seen = request;
        return http.Response(jsonEncode({'access_token': 'tok'}), 200);
      }),
      'example.social',
      redirect,
    );

    final token = await auth.exchangeCode(
      const MastodonApp(clientId: 'cid', clientSecret: 'sec'),
      code: 'abc',
      codeVerifier: 'ver',
    );

    expect(token, 'tok');
    expect(seen.url.path, '/oauth/token');
    final body = jsonDecode(seen.body) as Map<String, dynamic>;
    expect(body['grant_type'], 'authorization_code');
    expect(body['code'], 'abc');
    expect(body['code_verifier'], 'ver');
    expect(body['client_secret'], 'sec');
  });

  test('a token error is surfaced', () async {
    final auth = MastodonAuth(
      MockClient((_) async => http.Response('{"error":"invalid_grant"}', 400)),
      'example.social',
      redirect,
    );

    expect(
      () => auth.exchangeCode(
        const MastodonApp(clientId: 'cid', clientSecret: 'sec'),
        code: 'abc',
        codeVerifier: 'ver',
      ),
      throwsA(isA<Exception>()),
    );
  });
}
