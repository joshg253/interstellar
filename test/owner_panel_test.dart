import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interstellar/src/controller/controller.dart';
import 'package:interstellar/src/controller/server.dart';
import 'package:interstellar/src/models/community.dart';
import 'package:interstellar/src/models/user.dart';
import 'package:interstellar/src/screens/explore/community_owner_panel.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

class _FakeController extends Fake implements AppController {
  _FakeController(this.serverSoftware);

  @override
  final ServerSoftware serverSoftware;

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

const _community = DetailedCommunityModel(
  id: 1,
  name: 'community',
  title: 'Community',
  icon: null,
  description: null,
  owner: null,
  moderators: [
    UserModel(
      id: 2,
      name: 'mod',
      avatar: null,
      createdAt: null,
      isBot: false,
      apId: null,
    ),
  ],
  subscriptionsCount: 0,
  threadCount: 0,
  threadCommentCount: 0,
  microblogCount: null,
  microblogCommentCount: null,
  isAdult: false,
  isUserSubscribed: null,
  isBlockedByUser: null,
  isPostingRestrictedToMods: false,
  notificationControlStatus: null,
  flairs: [],
  apId: null,
);

Future<void> _pump(
  WidgetTester tester,
  ServerSoftware software,
  Widget child,
) => tester.pumpWidget(
  ChangeNotifierProvider<AppController>.value(
    value: _FakeController(software),
    child: MaterialApp(home: Scaffold(body: child)),
  ),
);

void main() {
  group('deletion tab', () {
    final tab = CommunityOwnerPanelDeletion(data: _community, onUpdate: (_) {});

    testWidgets('Lemmy cannot remove the icon or delete, so no buttons', (
      tester,
    ) async {
      await _pump(tester, ServerSoftware.lemmy, tab);

      expect(find.text('Remove icon'), findsNothing);
      expect(find.text('Delete Community'), findsNothing);
      expect(find.textContaining('not available on Lemmy'), findsOneWidget);
    });

    for (final software in [ServerSoftware.mbin, ServerSoftware.piefed]) {
      testWidgets('$software keeps both buttons', (tester) async {
        await _pump(tester, software, tab);

        expect(find.text('Remove icon'), findsOneWidget);
        expect(find.text('Delete Community'), findsOneWidget);
      });
    }
  });

  group('moderators tab', () {
    final tab = CommunityOwnerPanelModerators(
      data: _community,
      onUpdate: (_) {},
    );

    testWidgets('PieFed cannot manage moderators, so no add control', (
      tester,
    ) async {
      await _pump(tester, ServerSoftware.piefed, tab);

      expect(find.text('Add'), findsNothing);
      expect(find.byIcon(Symbols.delete_outline_rounded), findsNothing);
      expect(find.textContaining('not available on PieFed'), findsOneWidget);
    });

    for (final software in [ServerSoftware.mbin, ServerSoftware.lemmy]) {
      testWidgets('$software keeps the add control', (tester) async {
        await _pump(tester, software, tab);

        expect(find.text('Add'), findsOneWidget);
        expect(find.byIcon(Symbols.delete_outline_rounded), findsOneWidget);
      });
    }
  });
}
