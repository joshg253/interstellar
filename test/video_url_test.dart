import 'package:flutter_test/flutter_test.dart';
import 'package:interstellar/src/utils/video_url.dart';

void main() {
  embeddedTests();
  test('a direct video file is playable as it is', () {
    for (final ext in ['mp4', 'webm', 'mov', 'm4v', 'MP4']) {
      final u = Uri.parse('https://cdn.example.com/a/v.$ext?x=1');
      expect(playableVideoUrl(u), u, reason: ext);
    }
  });

  test('an imgur gifv page is its mp4', () {
    expect(
      playableVideoUrl(Uri.parse('https://i.imgur.com/bZEoMuz.gifv')),
      Uri.parse('https://i.imgur.com/bZEoMuz.mp4'),
    );
  });

  test('pages, images, http and other schemes are not video', () {
    for (final u in [
      'https://example.com/watch',
      'https://i.imgur.com/a.png',
      'https://example.com/clip.gifv',
      'http://cdn.example.com/v.mp4',
      'http://i.imgur.com/a.gifv',
      'file:///sdcard/v.mp4',
      'javascript:alert(1)',
    ]) {
      expect(playableVideoUrl(Uri.parse(u)), isNull, reason: u);
    }
  });
}

void embeddedTests() {
  group('embeddedVideoFile', () {
    test('a video file is kept', () {
      expect(
        embeddedVideoFile('https://i.example/v.mp4'),
        Uri.parse('https://i.example/v.mp4'),
      );
    });

    test('a web page, nothing or an insecure address is not', () {
      expect(
        embeddedVideoFile('https://video.example/videos/embed/abc'),
        isNull,
      );
      expect(embeddedVideoFile('http://i.example/v.mp4'), isNull);
      expect(embeddedVideoFile(null), isNull);
      expect(embeddedVideoFile(''), isNull);
    });
  });
}
