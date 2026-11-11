import 'package:flutter_test/flutter_test.dart';
import 'package:interstellar/src/models/post.dart';

Map<String, Object?> _post(Map<String, Object?> extra) => {
  'post_view': {
    'post': {
      'id': 1,
      'title': 'Pictures',
      'language_id': 0,
      'nsfw': false,
      'sticky': false,
      'locked': false,
      'published': '2026-01-01T00:00:00Z',
      'post_type': 'Gallery',
      'thumbnail_url': 'https://img.example/thumb.webp',
      'ap_id': 'https://piefed.example/post/1',
      ...extra,
    },
    'creator': {
      'id': 2,
      'user_name': 'alice',
      'local': true,
      'bot': false,
      'published': '2025-01-01T00:00:00Z',
      'actor_id': 'https://piefed.example/u/alice',
    },
    'community': {
      'id': 3,
      'name': 'pics',
      'title': 'Pics',
      'local': true,
      'published': '2025-01-01T00:00:00Z',
      'actor_id': 'https://piefed.example/c/pics',
      'nsfw': false,
      'restricted_to_mods': false,
      'removed': false,
      'deleted': false,
      'hidden': false,
    },
    'counts': {
      'comments': 0,
      'upvotes': 1,
      'downvotes': 0,
      'newest_comment_time': '2026-01-01T00:00:00Z',
    },
    'saved': false,
  },
};

void main() {
  test('a gallery post keeps all its images', () {
    final post = PostModel.fromPiefed(
      _post({
        'gallery': ['https://img.example/a.jpg', 'https://img.example/b.jpg'],
      }),
      langCodeIdPairs: const [],
    );
    expect(post.gallery, [
      'https://img.example/a.jpg',
      'https://img.example/b.jpg',
    ]);
  });

  test('a post without a gallery has none', () {
    final post = PostModel.fromPiefed(_post({}), langCodeIdPairs: const []);
    expect(post.gallery, isEmpty);
  });
}
