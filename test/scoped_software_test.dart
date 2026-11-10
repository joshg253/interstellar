import 'package:flutter_test/flutter_test.dart';
import 'package:interstellar/src/controller/server.dart';
import 'package:interstellar/src/widgets/account_scope.dart';

void main() {
  test('menus use the scoped account software, else the selected one', () {
    expect(
      scopedSoftware(ServerSoftware.mastodon, ServerSoftware.mbin),
      ServerSoftware.mastodon,
    );
    expect(scopedSoftware(null, ServerSoftware.mbin), ServerSoftware.mbin);
  });
}
