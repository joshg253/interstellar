import 'package:flutter_test/flutter_test.dart';
import 'package:interstellar/src/utils/video_url.dart';

void main() {
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
