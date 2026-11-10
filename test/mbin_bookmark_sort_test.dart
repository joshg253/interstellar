import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:interstellar/src/api/bookmark.dart';
import 'package:interstellar/src/api/client.dart';
import 'package:interstellar/src/controller/server.dart';

void main() {
  Future<Map<String, String>> asked({String? sort, String? list}) async {
    late Map<String, String> query;
    final api = APIBookmark(
      ServerClient(
        httpClient: MockClient((r) async {
          query = r.url.queryParameters;
          return http.Response(
            jsonEncode({
              'items': <Object?>[],
              'pagination': {'currentPage': 1, 'maxPage': 1},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
        software: ServerSoftware.mbin,
        domain: 'mbin.example.com',
      ),
    );
    await (sort == null
        ? api.list(list: list)
        : api.list(list: list, sort: sort));
    return query;
  }

  test('bookmarks are newest first unless a sort is given', () async {
    expect((await asked())['sort'], 'newest');
  });

  test('the chosen sort and list are sent to Mbin', () async {
    final q = await asked(sort: 'top', list: 'Reading');
    expect(q['sort'], 'top');
    expect(q['list'], 'Reading');
  });
}
