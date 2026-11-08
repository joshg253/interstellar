import 'package:flutter_test/flutter_test.dart';
import 'package:interstellar/src/widgets/paging.dart';
import 'package:logger/logger.dart';

void main() {
  test('a failed page can be fetched again', () async {
    var failNext = false;
    final requested = <int>[];
    final controller = AdvancedPagingController<int, int, int>(
      logger: Logger(level: Level.off),
      firstPageKey: 1,
      getItemId: (item) => item,
      fetchPage: (page) async {
        requested.add(page);
        if (failNext) {
          failNext = false;
          throw Exception('offline');
        }
        return ([page], page + 1);
      },
    );

    await controller.fetchNextPage();
    failNext = true;
    await controller.fetchNextPage();
    expect(controller.value.error, isNotNull);

    await controller.fetchNextPage();

    expect(requested, [1, 2, 2]);
    expect(controller.value.pages, [
      [1],
      [2],
    ]);
    expect(controller.value.error, isNull);
  });

  test('a failed first page can be fetched again', () async {
    var failNext = true;
    final requested = <int>[];
    final controller = AdvancedPagingController<int, int, int>(
      logger: Logger(level: Level.off),
      firstPageKey: 1,
      getItemId: (item) => item,
      fetchPage: (page) async {
        requested.add(page);
        if (failNext) {
          failNext = false;
          throw Exception('offline');
        }
        return ([page], null);
      },
    );

    await controller.fetchNextPage();
    expect(controller.value.error, isNotNull);
    expect(controller.value.hasNextPage, isTrue);

    await controller.fetchNextPage();

    expect(requested, [1, 1]);
    expect(controller.value.pages, [
      [1],
    ]);
    expect(controller.value.error, isNull);
  });
}
