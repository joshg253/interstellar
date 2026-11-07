import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:http/http.dart' as http;
import 'package:interstellar/src/utils/utils.dart';

final bool isWebViewSupported = PlatformIs.mobile;

final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

final Set<String> _pendingErrorToasts = {};

void _showSnackBarToast(String message) => scaffoldMessengerKey.currentState
    ?.showSnackBar(SnackBar(content: Text(message), showCloseIcon: true));

/// Shows an error toast; replaceable in tests.
@visibleForTesting
void Function(String message) errorToastPresenter = _showSnackBarToast;

/// Shows [message] in a snackbar once the current frame is done.
///
/// Errors are often reported mid-build, where showing a snackbar throws again
/// and re-enters the error handler. A message already waiting is dropped, and
/// a failure to show it is swallowed: reporting it would queue another toast,
/// and so on every frame.
void showErrorToast(String message) {
  if (!_pendingErrorToasts.add(message)) return;
  SchedulerBinding.instance.addPostFrameCallback((_) {
    _pendingErrorToasts.remove(message);
    try {
      errorToastPresenter(message);
    } catch (e, st) {
      // The messenger may be gone (e.g. while accounts are switching). Not
      // reported as an error, which would queue another toast; debugPrint
      // does not go through FlutterError.onError.
      debugPrint('error toast failed: $e\n$st');
    }
  });
  SchedulerBinding.instance.ensureVisualUpdate();
}

late final String appVersion;
late final http.Client appHttpClient;

final Uri oauthRedirectUri = Uri.parse(
  PlatformIs.web
      ? '${Uri.base.origin}/auth.html'
      : PlatformIs.linux || PlatformIs.windows
      ? 'http://localhost:46837'
      : 'interstellar://auth',
);
