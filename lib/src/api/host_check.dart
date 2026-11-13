import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:interstellar/src/utils/globals.dart';

/// Why a server did not pass a check.
enum HostFailure {
  /// No connection: unknown host, refused, timed out.
  network,

  /// It answered with an error status (bot blocking looks like this too).
  http,

  /// It answered, but not like a fediverse server.
  notFediverse,
}

/// What went wrong with one server, and how long it has been going on.
class HostProblem {
  const HostProblem({
    required this.kind,
    required this.detail,
    required this.since,
    required this.last,
    required this.checks,
  });

  factory HostProblem.fromJson(Map<String, dynamic> json) => HostProblem(
    kind: HostFailure.values.byName(json['kind'] as String),
    detail: json['detail'] as String,
    since: DateTime.parse(json['since'] as String),
    last: DateTime.parse(json['last'] as String),
    checks: json['checks'] as int,
  );

  final HostFailure kind;
  final String detail;

  /// The first failed check of the current run of failures.
  final DateTime since;
  final DateTime last;

  /// Failed checks in a row.
  final int checks;

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'detail': detail,
    'since': since.toIso8601String(),
    'last': last.toIso8601String(),
    'checks': checks,
  };
}

/// Asks [host] for its nodeinfo document: null if it answers like a fediverse
/// server, else what is wrong.
Future<({HostFailure kind, String detail})?> probeHost(
  String host, {
  http.Client? client,
}) async {
  final web = client ?? appHttpClient;
  try {
    final res = await web
        .get(Uri.https(host, '/.well-known/nodeinfo'))
        .timeout(const Duration(seconds: 10));
    if (res.statusCode >= 400) {
      return (kind: HostFailure.http, detail: 'HTTP ${res.statusCode}');
    }
    try {
      final json = jsonDecode(res.body);
      if (json is Map && json['links'] is List) return null;
    } catch (_) {}
    return (kind: HostFailure.notFediverse, detail: 'no nodeinfo');
  } on TimeoutException {
    return (kind: HostFailure.network, detail: 'timed out');
  } on SocketException catch (e) {
    return (kind: HostFailure.network, detail: e.message);
  } catch (e) {
    return (kind: HostFailure.network, detail: '$e');
  }
}
