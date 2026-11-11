import 'package:flutter_test/flutter_test.dart';
import 'package:interstellar/src/models/post.dart';

Map<String, Object?> _post(Map<String, Object?> extra) => {
  'post_view': {
    'post': {
      'id': 1,
      'name': 'Boat vs. wave',
      'url': 'https://m.example/@alice/117593507593765521',
      'language_id': 0,
      'nsfw': false,
      'featured_community': false,
      'featured_local': false,
      'locked': false,
      'published': '2026-01-01T00:00:00Z',
      'deleted': false,
      'removed': false,
      'ap_id': 'https://lemmy.example/post/1',
      ...extra,
    },
    'creator': {
      'id': 2,
      'name': 'alice',
      'published': '2025-01-01T00:00:00Z',
      'actor_id': 'https://lemmy.example/u/alice',
      'local': true,
      'deleted': false,
      'bot_account': false,
    },
    'community': {
      'id': 3,
      'name': 'videos',
      'title': 'Videos',
      'published': '2025-01-01T00:00:00Z',
      'removed': false,
      'deleted': false,
      'nsfw': false,
      'actor_id': 'https://lemmy.example/c/videos',
      'local': true,
      'hidden': false,
      'posting_restricted_to_mods': false,
    },
  },
};

void main() {
  test('the video Lemmy found behind a link is kept', () {
    final post = PostModel.fromLemmy(
      _post({'embed_video_url': 'https://files.example/v.mp4'}),
      langCodeIdPairs: const [],
    );
    expect(post.embedVideoUrl, 'https://files.example/v.mp4');
  });

  test('a post without one has none', () {
    final post = PostModel.fromLemmy(_post({}), langCodeIdPairs: const []);
    expect(post.embedVideoUrl, isNull);
  });
}
