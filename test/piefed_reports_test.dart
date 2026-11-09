import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:interstellar/src/api/client.dart';
import 'package:interstellar/src/api/community_moderation.dart';
import 'package:interstellar/src/controller/server.dart';
import 'package:interstellar/src/models/post.dart';

Map<String, Object?> _person(int id) => {
  'id': id,
  'user_name': 'user$id',
  'local': true,
  'bot': false,
  'published': '2025-01-01T00:00:00Z',
  'actor_id': 'https://example.com/u/user$id',
};

Map<String, Object?> _reportView({
  required bool resolved,
  bool removed = false,
  bool deleted = false,
}) => {
  'post_report': {
    'id': 5,
    'creator_id': 2,
    'post_id': 11,
    'reason': 'spam',
    'resolved': resolved,
    'published': '2025-01-02T00:00:00Z',
  },
  'post': {
    'id': 11,
    'title': 'A post',
    'body': 'text',
    'published': '2025-01-01T00:00:00Z',
    'language_id': 0,
    'nsfw': false,
    'sticky': false,
    'locked': false,
    'removed': removed,
    'deleted': deleted,
    'ap_id': 'https://example.com/post/11',
  },
  'community': {
    'id': 7,
    'name': 'test',
    'title': 'Test',
    'local': true,
    'nsfw': false,
    'restricted_to_mods': false,
    'actor_id': 'https://example.com/c/test',
  },
  'counts': {
    'comments': 0,
    'upvotes': 1,
    'downvotes': 0,
    'newest_comment_time': '2025-01-01T00:00:00Z',
  },
  // The reporter, as the server names the `creator` of a report view.
  'creator': _person(2),
  'post_creator': _person(3),
  'saved': false,
};

ServerClient _client(
  List<http.Request> requests, {
  bool listRemoved = false,
  bool listDeleted = false,
}) {
  var removed = listRemoved;
  return ServerClient(
    httpClient: MockClient((request) async {
      requests.add(request);
      final path = request.url.path;
      if (path.endsWith('/site')) {
        return http.Response(
          jsonEncode({
            'site': {
              'all_languages': [
                {'id': 0, 'code': 'und'},
              ],
            },
          }),
          200,
        );
      }
      if (path.endsWith('/post/report/list')) {
        return http.Response(
          jsonEncode({
            'post_reports': [
              _reportView(
                resolved: listRemoved,
                removed: listRemoved,
                deleted: listDeleted,
              ),
            ],
            'next_page': '2',
          }),
          200,
        );
      }
      if (path.endsWith('/post/remove')) {
        removed = (jsonDecode(request.body) as Map)['removed']! as bool;
        return http.Response('{}', 200);
      }
      if (path.endsWith('/post/report/resolve')) {
        return http.Response(
          jsonEncode({
            'post_report_view': _reportView(resolved: true, removed: removed),
          }),
          200,
        );
      }
      return http.Response('{}', 404);
    }),
    software: ServerSoftware.piefed,
    domain: 'example.com',
  );
}

void main() {
  test(
    'PieFed listReports asks for the community and parses the views',
    () async {
      final requests = <http.Request>[];
      final list = await APICommunityModeration(
        _client(requests),
      ).listReports(7, status: ReportStatus.pending);

      final query = requests
          .firstWhere((r) => r.url.path.endsWith('/list'))
          .url
          .queryParameters;
      expect(query['community_id'], '7');
      expect(query['unresolved_only'], 'true');
      expect(list.nextPage, '2');
      final report = list.items.single;
      expect(report.id, 5);
      expect(report.reason, 'spam');
      expect(report.status, ReportStatus.pending);
      expect(report.reportedBy!.name, 'user2');
      expect(report.reportedUser!.name, 'user3');
      expect(report.subjectPost!.id, 11);
      expect(report.subjectPost!.user.name, 'user3');
    },
  );

  for (final accept in [true, false]) {
    test(
      'PieFed ${accept ? 'accept' : 'reject'}Report resolves the report',
      () async {
        final requests = <http.Request>[];
        final moderation = APICommunityModeration(_client(requests));
        final report = accept
            ? await moderation.acceptReport(7, 5, 11)
            : await moderation.rejectReport(7, 5, 11);

        final calls = requests
            .where((r) => !r.url.path.endsWith('/site'))
            .toList();
        // The post is changed before the report is resolved.
        expect(
          [
            for (final r in calls)
              '${r.method} ${r.url.path.split('/api/alpha').last}',
          ],
          ['POST /post/remove', 'PUT /post/report/resolve'],
        );
        final bodies = {
          for (final r in calls)
            r.url.path.split('/api/alpha').last: jsonDecode(r.body),
        };
        expect(bodies['/post/report/resolve'], {
          'report_id': 5,
          'resolved': true,
        });
        expect(bodies['/post/remove'], {
          'post_id': 11,
          'removed': accept,
          'reason': 'Moderated',
        });
        expect(report.id, 5);
        expect(
          report.status,
          accept ? ReportStatus.approved : ReportStatus.rejected,
        );
        expect(
          report.subjectPost!.visibility,
          accept ? PostVisibility.trashed : PostVisibility.visible,
        );
      },
    );
  }

  test('a post both removed and deleted still reads as approved', () async {
    final list = await APICommunityModeration(
      _client([], listRemoved: true, listDeleted: true),
    ).listReports(7, status: ReportStatus.approved);

    expect(list.items.single.status, ReportStatus.approved);
    expect(list.items.single.subjectPost!.visibility, PostVisibility.trashed);
  });

  test('a resolved report whose post was removed reads as approved', () async {
    final list = await APICommunityModeration(
      _client([], listRemoved: true),
    ).listReports(7, status: ReportStatus.approved);

    expect(list.items.single.status, ReportStatus.approved);
  });
}
