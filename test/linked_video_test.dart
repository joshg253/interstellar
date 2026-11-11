import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:interstellar/src/utils/linked_video.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  gifHostTests();
  peertubeTests();
  group('mastodonStatusRef', () {
    test('status links are recognized', () {
      expect(
        mastodonStatusRef(
          Uri.parse('https://mastodon.example/@alice/117593507593765521'),
        ),
        ('mastodon.example', '117593507593765521'),
      );
      expect(
        mastodonStatusRef(
          Uri.parse('https://m.example/users/alice/statuses/1234567'),
        ),
        ('m.example', '1234567'),
      );
    });

    test('other links are not', () {
      for (final link in [
        'https://example.com/@alice',
        'https://example.com/@alice/about',
        'https://example.com/post/123456',
        'http://m.example/@alice/117593507593765521',
        'https://example.com/@alice/12',
      ]) {
        expect(mastodonStatusRef(Uri.parse(link)), isNull, reason: link);
      }
    });
  });

  group('mastodonStatusVideo', () {
    final link = Uri.parse('https://m.example/@alice/117593507593765521');

    test('plays the status video, asking only for its public page', () async {
      Uri? asked;
      final client = MockClient((r) async {
        asked = r.url;
        return _json({
          'media_attachments': [
            {'type': 'image', 'url': 'https://m.example/a.png'},
            {'type': 'video', 'url': 'https://files.example/v.mp4'},
          ],
        });
      });

      final video = await linkedVideo(link, client, useCache: false);

      expect(video, Uri.parse('https://files.example/v.mp4'));
      expect(
        asked.toString(),
        'https://m.example/api/v1/statuses/117593507593765521',
      );
    });

    test('a gifv attachment counts', () async {
      final client = MockClient(
        (r) async => _json({
          'media_attachments': [
            {'type': 'gifv', 'url': 'https://files.example/g.mp4'},
          ],
        }),
      );
      expect(
        await linkedVideo(link, client, useCache: false),
        Uri.parse('https://files.example/g.mp4'),
      );
    });

    test('no video, a refusal, odd data or a dead server give null', () async {
      for (final response in <http.Response Function()>[
        () => _json({'media_attachments': <Object>[]}),
        () => http.Response('no', 401),
        () => http.Response('<html>', 200),
        () => _json({'media_attachments': 'x'}),
        () => _json({
          'media_attachments': [
            {'type': 'video', 'url': 'http://insecure/v.mp4'},
          ],
        }),
      ]) {
        final client = MockClient((r) async => response());
        expect(await linkedVideo(link, client, useCache: false), isNull);
      }
      final dead = MockClient((r) async => throw http.ClientException('down'));
      expect(await linkedVideo(link, dead, useCache: false), isNull);
    });

    test('a link that is not a status is not fetched', () async {
      var calls = 0;
      final client = MockClient((r) async {
        calls++;
        return _json({});
      });
      expect(
        await linkedVideo(Uri.parse('https://example.com/x'), client),
        isNull,
      );
      expect(calls, 0);
    });
  });
}

void peertubeTests() {
  group('peertubeVideoRef', () {
    test('watch links are recognized', () {
      expect(
        peertubeVideoRef(
          Uri.parse('https://video.example/w/cNnWa6uLs9kwpsomdwgfF7'),
        ),
        ('video.example', 'cNnWa6uLs9kwpsomdwgfF7'),
      );
      expect(
        peertubeVideoRef(
          Uri.parse(
            'https://video.example/videos/watch/cc2fae57-f25c-4027-95cd-90a9eeb8f8ce',
          ),
        ),
        ('video.example', 'cc2fae57-f25c-4027-95cd-90a9eeb8f8ce'),
      );
    });

    test('other links are not', () {
      for (final link in [
        'https://example.com/w/',
        'https://example.com/w/a/b',
        'https://example.com/videos/watch/',
        'https://example.com/watch?v=abc',
        'http://example.com/w/cNnWa6uLs9kwpsomdwgfF7',
      ]) {
        expect(peertubeVideoRef(Uri.parse(link)), isNull, reason: link);
      }
    });
  });

  group('linkedVideo for PeerTube', () {
    final link = Uri.parse('https://video.example/w/cNnWa6uLs9kwpsomdwgfF7');

    test('prefers a plain file, then the stream playlist', () async {
      Uri? asked;
      final withFile = MockClient((r) async {
        asked = r.url;
        return _json({
          'files': [
            {'fileUrl': 'https://cdn.example/v-720.mp4'},
          ],
          'streamingPlaylists': [
            {'playlistUrl': 'https://cdn.example/master.m3u8'},
          ],
        });
      });
      expect(
        await linkedVideo(link, withFile, useCache: false),
        Uri.parse('https://cdn.example/v-720.mp4'),
      );
      expect(
        asked.toString(),
        'https://video.example/api/v1/videos/cNnWa6uLs9kwpsomdwgfF7',
      );

      final streamOnly = MockClient(
        (r) async => _json({
          'files': <Object>[],
          'streamingPlaylists': [
            {'playlistUrl': 'https://cdn.example/master.m3u8'},
          ],
        }),
      );
      expect(
        await linkedVideo(link, streamOnly, useCache: false),
        Uri.parse('https://cdn.example/master.m3u8'),
      );
    });

    test('a refusal, a live stream or odd data give null', () async {
      for (final response in <http.Response Function()>[
        () => http.Response('no', 404),
        () => _json({'files': <Object>[], 'streamingPlaylists': <Object>[]}),
        () => _json({'files': 'x'}),
        () => _json({
          'files': [
            {'fileUrl': 'http://insecure/v.mp4'},
          ],
        }),
      ]) {
        final client = MockClient((r) async => response());
        expect(await linkedVideo(link, client, useCache: false), isNull);
      }
    });
  });
}

void gifHostTests() {
  group('gifHostRef', () {
    test('watch and embed pages are recognized', () {
      expect(
        gifHostRef(Uri.parse('https://www.$gifHost/watch/SomeSlugHere')),
        'someslughere',
      );
      expect(gifHostRef(Uri.parse('https://$gifHost/ifr/abc')), 'abc');
    });

    test('other links are not', () {
      for (final link in [
        'https://www.$gifHost/users/someone',
        'https://www.$gifHost/watch/',
        'https://example.com/watch/abc',
        'http://www.$gifHost/watch/abc',
      ]) {
        expect(gifHostRef(Uri.parse(link)), isNull, reason: link);
      }
    });
  });

  group('linkedVideo for the gif host', () {
    final link = Uri.parse('https://www.$gifHost/watch/SomeSlugHere');

    test(
      'asks for a guest token, then for the gif, and takes the hd file',
      () async {
        final seen = <String>[];
        String? auth;
        final client = MockClient((r) async {
          seen.add(r.url.path);
          if (r.url.path == '/v2/auth/temporary')
            return _json({'token': 't0k'});
          auth = r.headers['Authorization'];
          return _json({
            'gif': {
              'urls': {
                'sd': 'https://m.example/sd.mp4',
                'hd': 'https://m.example/hd.mp4',
              },
            },
          });
        });

        final video = await linkedVideo(link, client, useCache: false);

        expect(video, Uri.parse('https://m.example/hd.mp4'));
        expect(seen, ['/v2/auth/temporary', '/v2/gifs/someslughere']);
        expect(auth, 'Bearer t0k');
      },
    );

    test('falls back to sd, and gives null on refusals or odd data', () async {
      final sdOnly = MockClient(
        (r) async => r.url.path == '/v2/auth/temporary'
            ? _json({'token': 't'})
            : _json({
                'gif': {
                  'urls': {'sd': 'https://m.example/sd.mp4'},
                },
              }),
      );
      expect(
        await linkedVideo(link, sdOnly, useCache: false),
        Uri.parse('https://m.example/sd.mp4'),
      );

      for (final response in <http.Response Function(Uri)>[
        (u) => http.Response('no', 403),
        (u) => u.path == '/v2/auth/temporary'
            ? _json({'token': 't'})
            : http.Response('gone', 404),
        (u) => u.path == '/v2/auth/temporary' ? _json({}) : _json({}),
        (u) => u.path == '/v2/auth/temporary'
            ? _json({'token': 't'})
            : _json({
                'gif': {
                  'urls': {'hd': 'http://insecure/v.mp4'},
                },
              }),
      ]) {
        final client = MockClient((r) async => response(r.url));
        expect(await linkedVideo(link, client, useCache: false), isNull);
      }
    });
  });
}
