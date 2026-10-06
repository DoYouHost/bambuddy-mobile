import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:bambuddy_mobile/data/library_repository.dart';
import 'package:bambuddy_mobile/data/queue_repository.dart';
import 'package:bambuddy_mobile/data/server_settings_repository.dart';
import 'package:bambuddy_mobile/features/queue/queue_removal.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';

/// A billing server, as the app's stop-gap reads it: the flag it detects
/// billing by, and the refusal it words when a new item has no cost center
/// (maziggy/bambuddy #3256).
///
/// Named `ws_…` to run last: billing on refuses every other test's queue
/// write, so it is switched off again afterwards.
void main() {
  group('billing', skip: contractSkipReason, () {
    test('the flag is readable and a new item is refused in words', () async {
      final dio = await authenticatedDio();
      final settings = ServerSettingsRepository(dio);
      final queue = QueueRepository(dio);
      final en = lookupAppLocalizations(const Locale('en'));
      final file = (await LibraryRepository(
        dio,
      ).listFiles()).firstWhere((f) => f.filename == 'contract-probe.3mf');

      // Queued before billing was switched on: no cost center.
      final before = {for (final i in await queue.fetch()) i.id};
      await queue.addFromLibraryFile(
        file.id,
        options: const QueueCreateOptions(manualStart: true),
      );
      final plain = (await queue.fetch()).firstWhere(
        (i) => !before.contains(i.id),
      );
      addTearDown(() => queue.delete(plain.id));

      await settings.update({'billing_enabled': true});
      addTearDown(() => settings.update({'billing_enabled': false}));

      final flags = await settings.fetchUiFlags();
      // 1.2.6+ has the flags; an older server only the full settings.
      expect(
        flags['billing_enabled'] ?? (await settings.fetch())['billing_enabled'],
        isTrue,
      );

      Future<String> refusal(Future<void> Function() write) async {
        try {
          await write();
        } on AppApiException catch (e) {
          return queueRefusal(en, e);
        }
        fail('a billing server must refuse a job with no cost center');
      }

      expect(
        await refusal(
          () => queue.addFromLibraryFile(
            file.id,
            options: const QueueCreateOptions(manualStart: true),
          ),
        ),
        en.queueBillingUseWeb,
      );
      // Every PATCH checks the budget, so the item queued before is stuck too.
      expect(
        await refusal(() => queue.updateItem(plain.id, manualStart: true)),
        en.queueBillingUseWeb,
      );

      // One queued in the web with a cost center reads back with it, and edits.
      final center =
          (await dio.post<Map<String, dynamic>>(
                '/api/v1/finance/cost-centers',
                data: {'name': 'Contract', 'total_budget': 1000},
              )).data!['id']
              as int;
      final created = (await dio.post<Map<String, dynamic>>(
        '/api/v1/queue/',
        data: {
          'library_file_id': file.id,
          'manual_start': true,
          'cost_center_id': center,
        },
      )).data!;
      final charged = QueueItem.fromJson(created);
      addTearDown(() => queue.delete(charged.id));
      expect(charged.costCenterId, center);
      await queue.updateItem(charged.id, manualStart: true);
    });
  });
}
