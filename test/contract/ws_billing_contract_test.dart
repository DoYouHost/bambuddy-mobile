import 'package:bambuddy_mobile/core/api/action_outcome.dart';
import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
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
      await settings.update({'billing_enabled': true});
      addTearDown(() => settings.update({'billing_enabled': false}));

      final flags = await settings.fetchUiFlags();
      // 1.2.6+ has the flags; an older server only the full settings.
      expect(
        flags['billing_enabled'] ?? (await settings.fetch())['billing_enabled'],
        isTrue,
      );

      final file = (await LibraryRepository(
        dio,
      ).listFiles()).firstWhere((f) => f.filename == 'contract-probe.3mf');
      final en = lookupAppLocalizations(const Locale('en'));
      try {
        await QueueRepository(dio).addFromLibraryFile(
          file.id,
          options: const QueueCreateOptions(manualStart: true),
        );
        fail('a billing server must refuse an item with no cost center');
      } on AppApiException catch (e) {
        expect(
          queueWriteMessage(en, ActionOutcome.failed(e)),
          en.queueBillingUseWeb,
        );
      }
    });
  });
}
