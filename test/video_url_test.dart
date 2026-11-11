import 'package:flutter_test/flutter_test.dart';
import 'package:interstellar/src/utils/video_url.dart';

void main() {
  embeddedTests();
  youTubeFrontEndTests();
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

void youTubeFrontEndTests() {
  group('youTubeWatchUrl', () {
    final watch = Uri.parse('https://www.youtube.com/watch?v=xjgqCq8UmXE');

    test('an Invidious or Piped embed or watch link is the YouTube video', () {
      for (final u in [
        'https://inv.nadeko.net/embed/xjgqCq8UmXE?list=RDxjgqCq8UmXE',
        'https://invidious.example.com/watch?v=xjgqCq8UmXE&t=3',
        'https://piped.example.com/watch?v=xjgqCq8UmXE',
        'https://yewtu.be/embed/xjgqCq8UmXE',
        'https://www.youtube.com/embed/xjgqCq8UmXE',
        'https://www.youtube-nocookie.com/embed/xjgqCq8UmXE',
      ]) {
        expect(youTubeWatchUrl(Uri.parse(u)), watch, reason: u);
      }
    });

    test('other sites, bad ids and plain http are not', () {
      for (final u in [
        'https://example.com/embed/xjgqCq8UmXE',
        'https://example.com/watch?v=xjgqCq8UmXE',
        'https://inv.nadeko.net/embed/short',
        'https://inv.nadeko.net/channel/xjgqCq8UmXE',
        'http://inv.nadeko.net/embed/xjgqCq8UmXE',
      ]) {
        expect(youTubeWatchUrl(Uri.parse(u)), isNull, reason: u);
      }
    });
  });
}
