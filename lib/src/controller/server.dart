import 'package:flutter/widgets.dart';

enum ServerSoftware {
  mbin,
  lemmy,
  piefed,
  mastodon;

  String get apiPathPrefix => switch (this) {
    ServerSoftware.mbin => '/api',
    ServerSoftware.lemmy => '/api/v3',
    ServerSoftware.piefed => '/api/alpha',
    ServerSoftware.mastodon => '/api/v1',
  };

  String get title => switch (this) {
    ServerSoftware.mbin => 'Mbin',
    ServerSoftware.lemmy => 'Lemmy',
    ServerSoftware.piefed => 'PieFed',
    ServerSoftware.mastodon => 'Mastodon',
  };

  Color get color => switch (this) {
    ServerSoftware.mbin => const Color(0xff4f2696),
    ServerSoftware.lemmy => const Color(0xff03a80e),
    ServerSoftware.piefed => const Color(0xff0e6ef9),
    ServerSoftware.mastodon => const Color(0xff6364ff),
  };

  /// Full-API types can be the app's selected account; the rest (Mastodon)
  /// only appear in the cross-account views.
  bool get canBeAppAccount => this != ServerSoftware.mastodon;

  /// Whether the type has moderated and favorited feeds and user settings.
  bool get hasPersonalFeeds => canBeAppAccount;

  // Use const ints as bitflags since using enums directly as bitflags is a bit awkward in dart.
  static const int mbinFlag = 1;
  static const int lemmyFlag = 2;
  static const int piefedFlag = 4;
  static const int mastodonFlag = 8;

  int get bitFlag => switch (this) {
    ServerSoftware.mbin => mbinFlag,
    ServerSoftware.lemmy => lemmyFlag,
    ServerSoftware.piefed => piefedFlag,
    ServerSoftware.mastodon => mastodonFlag,
  };
}
