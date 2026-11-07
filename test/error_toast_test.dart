import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interstellar/src/utils/globals.dart';

class _ThrowsInBuild extends StatelessWidget {
  const _ThrowsInBuild();

  @override
  Widget build(BuildContext context) {
    // what the global error handler does when an error is reported mid-build
    showErrorToast('boom');
    return const SizedBox();
  }
}

void main() {
  errorToastLoopTests();
  testWidgets('toast requested during build does not throw', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: scaffoldMessengerKey,
        home: const Scaffold(body: _ThrowsInBuild()),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('boom'), findsOneWidget);
  });

  testWidgets('repeated identical errors show one toast', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: scaffoldMessengerKey,
        home: const Scaffold(body: SizedBox()),
      ),
    );

    final shown = <String>[];
    final original = errorToastPresenter;
    errorToastPresenter = shown.add;
    addTearDown(() => errorToastPresenter = original);

    for (var i = 0; i < 20; i++) {
      showErrorToast('same');
    }
    showErrorToast('other');
    await tester.pump();

    // one per distinct message; a snackbar count would hide a queue
    expect(shown, ['same', 'other']);
  });
}

void errorToastLoopTests() {
  testWidgets('a toast that cannot be shown does not report another error', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: scaffoldMessengerKey,
        home: const Scaffold(body: SizedBox()),
      ),
    );
    final original = errorToastPresenter;
    errorToastPresenter = (_) => throw StateError('messenger is gone');
    addTearDown(() => errorToastPresenter = original);

    showErrorToast('stuck');
    await tester.pump();

    // the failure is swallowed, not turned into a new error (and a new toast)
    expect(tester.takeException(), isNull);
  });
}
