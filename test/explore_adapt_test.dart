import 'package:flutter_test/flutter_test.dart';
import 'package:interstellar/src/controller/server.dart';
import 'package:interstellar/src/screens/explore/explore_screen.dart';

void main() {
  ({ExploreType type, ExploreFilter filter}) adapt(
    ExploreType type,
    ExploreFilter filter,
    ServerSoftware software, {
    bool loggedIn = true,
  }) => adaptExploreForServer(
    type: type,
    filter: filter,
    software: software,
    loggedIn: loggedIn,
  );

  test('a choice both servers offer is kept', () {
    final r = adapt(
      ExploreType.communities,
      ExploreFilter.subscribed,
      ServerSoftware.lemmy,
    );
    expect(r.type, ExploreType.communities);
    expect(r.filter, ExploreFilter.subscribed);
  });

  test('domains only exist on Mbin', () {
    expect(
      adapt(ExploreType.domains, ExploreFilter.all, ServerSoftware.lemmy).type,
      ExploreType.communities,
    );
    expect(
      adapt(ExploreType.domains, ExploreFilter.all, ServerSoftware.mbin).type,
      ExploreType.domains,
    );
  });

  test('feeds and topics only exist on PieFed', () {
    expect(
      adapt(ExploreType.feeds, ExploreFilter.all, ServerSoftware.mbin).type,
      ExploreType.communities,
    );
    expect(
      adapt(ExploreType.topics, ExploreFilter.all, ServerSoftware.piefed).type,
      ExploreType.topics,
    );
  });

  test('a filter the new server lacks falls back to all', () {
    // Lemmy has no "followed people" filter; Mbin has no local people filter.
    expect(
      adapt(
        ExploreType.people,
        ExploreFilter.subscribed,
        ServerSoftware.lemmy,
      ).filter,
      ExploreFilter.all,
    );
    expect(
      adapt(
        ExploreType.people,
        ExploreFilter.local,
        ServerSoftware.mbin,
      ).filter,
      ExploreFilter.all,
    );
    expect(
      adapt(
        ExploreType.communities,
        ExploreFilter.blocked,
        ServerSoftware.lemmy,
      ).filter,
      ExploreFilter.all,
    );
  });

  test('a guest loses the signed-in filters', () {
    expect(
      adapt(
        ExploreType.communities,
        ExploreFilter.subscribed,
        ServerSoftware.lemmy,
        loggedIn: false,
      ).filter,
      ExploreFilter.all,
    );
    expect(
      adapt(
        ExploreType.communities,
        ExploreFilter.local,
        ServerSoftware.lemmy,
        loggedIn: false,
      ).filter,
      ExploreFilter.local,
    );
  });
}
