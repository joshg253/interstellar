import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:interstellar/src/api/client.dart';

/// Mastodon OAuth: register an app on the server, send the user to the
/// authorize page, trade the returned code for an access token. Tokens do not
/// expire and have no refresh token, so the app is only needed while signing
/// in and is registered anew each time.
const mastodonScopes = 'read write follow';

class MastodonApp {
  const MastodonApp({required this.clientId, required this.clientSecret});

  final String clientId;
  final String clientSecret;
}

class MastodonAuthorization {
  const MastodonAuthorization(this.url, this.codeVerifier, this.state);

  final Uri url;
  final String codeVerifier;

  /// Echoed back on the redirect; a different value is a forged callback.
  final String state;
}

class MastodonAuth {
  MastodonAuth(this.httpClient, this.domain, this.redirectUri);

  final http.Client httpClient;
  final String domain;
  final Uri redirectUri;

  Future<MastodonApp> registerApp() async {
    final url = Uri.https(domain, '/api/v1/apps');
    final response = await httpClient.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'client_name': 'Interstellar',
        'redirect_uris': redirectUri.toString(),
        'scopes': mastodonScopes,
        'website': 'https://github.com/interstellar-app/interstellar',
      }),
    );
    ServerClient.checkResponseSuccess(url, response);

    final json = response.bodyJson;
    return MastodonApp(
      clientId: json['client_id']! as String,
      clientSecret: json['client_secret']! as String,
    );
  }

  /// PKCE is ignored by servers that predate it, and protects the code on
  /// those that support it.
  MastodonAuthorization authorization(MastodonApp app) {
    final random = Random.secure();
    final state = base64UrlEncode(
      List.generate(16, (_) => random.nextInt(256)),
    ).replaceAll('=', '');
    final verifier = base64UrlEncode(
      List.generate(32, (_) => random.nextInt(256)),
    ).replaceAll('=', '');
    final challenge = base64UrlEncode(
      sha256.convert(ascii.encode(verifier)).bytes,
    ).replaceAll('=', '');

    return MastodonAuthorization(
      Uri.https(domain, '/oauth/authorize', {
        'response_type': 'code',
        'client_id': app.clientId,
        'redirect_uri': redirectUri.toString(),
        'scope': mastodonScopes,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'state': state,
      }),
      verifier,
      state,
    );
  }

  Future<String> exchangeCode(
    MastodonApp app, {
    required String code,
    required String codeVerifier,
  }) async {
    final url = Uri.https(domain, '/oauth/token');
    final response = await httpClient.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'grant_type': 'authorization_code',
        'client_id': app.clientId,
        'client_secret': app.clientSecret,
        'redirect_uri': redirectUri.toString(),
        'code': code,
        'code_verifier': codeVerifier,
        'scope': mastodonScopes,
      }),
    );
    ServerClient.checkResponseSuccess(url, response);

    return response.bodyJson['access_token']! as String;
  }
}
