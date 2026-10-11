import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/current_user.dart';
import 'package:bambuddy_mobile/data/library_repository.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/data/queue_repository.dart';
import 'package:bambuddy_mobile/features/queue/queue_removal.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';

/// Server #1620: a user without `queue:start_unreviewed` has every job held
/// for a reviewer. The app reads the gate off a printer row (#694), so what is
/// checked here is that the row and the hold agree on every server generation.
void main() {
  group('queue review gate contract', skip: contractSkipReason, () {
    late Dio admin;
    late Dio student;
    late CurrentUser me;
    final en = lookupAppLocalizations(const Locale('en'));

    setUpAll(() async {
      admin = await authenticatedDio();
      // What a group that may queue held before #1620, less the right the
      // upgrade grants it — the student an admin took it away from.
      (dio: student, :me) = await contractUser(admin, const [
        'printers:read',
        'library:read_all',
        'queue:read_own',
        'queue:create',
        'queue:update_own',
        'queue:delete_own',
      ]);
    });

    test('the printer row says whether the job is held, and the hold is '
        'refused in words the app knows', () async {
      expect(me.can(Permissions.queueStartUnreviewed), isFalse);
      expect(me.can(Permissions.queueUpdateAll), isFalse);

      final printers = PrintersRepository(student);
      await printers.fetchPrinters();
      final gate = printers.reviewGateCapability.observedAnswer;
      expect(gate, isNotNull, reason: 'the seed has a printer to read');

      final file = (await LibraryRepository(admin).listFiles()).first;
      final queue = QueueRepository(student);
      await queue.addFromLibraryFile(file.id);
      final mine = (await queue.fetch()).lastWhere(
        (i) => i.libraryFileId == file.id && i.createdById == me.id,
      );
      addTearDown(() => queue.delete(mine.id));

      expect(
        mine.manualStart,
        gate,
        reason: 'the app asked for no wait; only the gate adds one',
      );
      if (gate != true) return;
      try {
        await queue.start(mine.id);
        fail('a held user started their own job');
      } on AppApiException catch (e) {
        expect(e.code, AppErrorCode.forbidden);
        expect(queueRefusal(en, e), en.queueAwaitingReviewRefused);
      }
    });
  });
}
