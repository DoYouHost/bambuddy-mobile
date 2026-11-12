import 'package:bambuddy_mobile/data/library_repository.dart';
import 'package:bambuddy_mobile/features/files/trash_screen.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
  /// The trash over the real repository; returns the requests it sent.
  Future<RequestLog> pump(WidgetTester tester) async {
    final dio = testDio();
    mockServer(dio)
      ..onGet(
        '/api/v1/library/trash',
        (server) => server.reply(200, {
          'items': [
            {'id': 7, 'filename': 'bracket.3mf', 'file_size': 1024},
          ],
        }),
      )
      ..onDelete('/api/v1/library/trash/7', (server) => server.reply(200, {}))
      ..onDelete('/api/v1/library/trash', (server) => server.reply(200, {}));
    final log = captureRequests(dio);
    await pumpPhone(
      tester,
      const TrashScreen(),
      overrides: [
        libraryRepositoryProvider.overrideWithValue(LibraryRepository(dio)),
      ],
    );
    await tester.pumpAndSettle();
    return log;
  }

  List<String> deletes(RequestLog log) => [
    for (final r in log.requests)
      if (r.method == 'DELETE') r.path,
  ];

  testWidgets('deleting one file for good asks, deletes it and says so', (
    tester,
  ) async {
    final log = await pump(tester);
    await tester.tap(byLogId('trash.delete'));
    await tester.pumpAndSettle();
    await tester.tap(byLogId('trash.hard_delete_confirm.confirm'));
    await tester.pumpAndSettle();

    expect(deletes(log), ['/api/v1/library/trash/7']);
    expect(find.text(pl.fmDeletedForever), findsOneWidget);
  });

  testWidgets('emptying the trash asks, empties it and says so', (
    tester,
  ) async {
    final log = await pump(tester);
    await tester.tap(byLogId('trash.purge'));
    await tester.pumpAndSettle();
    await tester.tap(byLogId('trash.purge_confirm.confirm'));
    await tester.pumpAndSettle();

    expect(deletes(log), ['/api/v1/library/trash']);
    expect(find.text(pl.fmDeletedForever), findsOneWidget);
  });

  testWidgets('backing out of the question deletes nothing', (tester) async {
    final log = await pump(tester);
    await tester.tap(byLogId('trash.purge'));
    await tester.pumpAndSettle();
    await tester.tap(byLogId('trash.purge_confirm.cancel'));
    await tester.pumpAndSettle();

    expect(deletes(log), isEmpty);
    expect(find.text(pl.fmDeletedForever), findsNothing);
  });
}
