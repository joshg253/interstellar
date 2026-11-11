import 'package:flutter_test/flutter_test.dart';
import 'package:interstellar/src/controller/server.dart';
import 'package:interstellar/src/models/post.dart';
import 'package:interstellar/src/utils/ap_urls.dart';

void main() {
  test('a post from another server gets no link built on the viewer host', () {
    // A Mastodon post carries a made-up numeric id: /post/<id> on a Lemmy
    // server would be a dead link.
    expect(
      postUrls(
        apId: 'https://social.example/@a/1',
        id: 4283753307889912,
        communityName: '',
        type: PostType.microblog,
        host: 'social.example',
        software: ServerSoftware.mastodon,
      ),
      [Uri.parse('https://social.example/@a/1')],
    );
  });

  test('a Lemmy post from elsewhere gets the shown account local link', () {
    expect(
      postUrls(
        apId: 'https://lemmy.ca/post/7',
        id: 5,
        communityName: 'c',
        type: PostType.thread,
        host: 'lemmy.world',
        software: ServerSoftware.lemmy,
      ),
      [
        Uri.parse('https://lemmy.world/post/5'),
        Uri.parse('https://lemmy.ca/post/7'),
      ],
    );
  });

  test('a local post gives one link', () {
    expect(
      postUrls(
        apId: 'https://lemmy.world/post/5',
        id: 5,
        communityName: 'c',
        type: PostType.thread,
        host: 'lemmy.world',
        software: ServerSoftware.lemmy,
      ),
      [Uri.parse('https://lemmy.world/post/5')],
    );
  });

  test('Mbin links use the magazine path', () {
    expect(
      postUrls(
        apId: null,
        id: 9,
        communityName: 'mag',
        type: PostType.thread,
        host: 'mbin.example',
        software: ServerSoftware.mbin,
      ),
      [Uri.parse('https://mbin.example/m/mag/t/9')],
    );
  });

  test('a comment from a Mastodon account has only its remote link', () {
    expect(
      commentUrls(
        apId: 'https://social.example/@a/2',
        id: 1,
        postId: 2,
        communityName: '',
        postType: PostType.microblog,
        host: 'social.example',
        software: ServerSoftware.mastodon,
      ),
      [Uri.parse('https://social.example/@a/2')],
    );
  });
}
