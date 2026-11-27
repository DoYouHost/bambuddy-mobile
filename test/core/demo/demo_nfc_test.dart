import 'dart:async';

import 'package:app_util/app_util.dart';
import 'package:bambuddy_mobile/core/app_context.dart';
import 'package:bambuddy_mobile/core/demo/demo_backend.dart';
import 'package:bambuddy_mobile/core/demo/demo_nfc.dart';
import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/core/nfc/nfc_reader.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_providers.dart';
import 'package:bambuddy_mobile/features/inventory/spool_scanner_screen.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

/// The demo shows every feature, NFC included, on a phone with none: its own
/// reader says NFC is on and "holds" a tag nobody knows, then a demo spool's.
void main() {
  test(
    'the reader is on, and holds a stranger first, then the demo spool',
    () async {
      const reader = DemoNfcReader(delay: Duration(milliseconds: 1));

      expect(await reader.status(), NfcStatus.ready);
      expect(await reader.tags().toList(), [
        demoNfcStrangerTag,
        demoNfcSpoolTag,
      ]);
    },
  );

  test('both tags are in the form the real reader emits', () {
    expect(normalizeTagUid(demoNfcSpoolTag), demoNfcSpoolTag);
    expect(normalizeTagUid(demoNfcStrangerTag), demoNfcStrangerTag);
  });

  test(
    'a demo spool carries the first tag, and none carries the other',
    () async {
      final dio = Dio(BaseOptions(baseUrl: DemoConfig.baseUrl))
        ..httpClientAdapter = DemoHttpClientAdapter(
          DemoBackend.instance.handle,
          latency: Duration.zero,
        );
      final shelf = InventoryState(
        spools: await NativeInventorySource(dio).fetchSpools(),
      );

      expect(shelf.spoolForTag(tagUid: demoNfcSpoolTag), isNotNull);
      expect(shelf.spoolForTag(tagUid: demoNfcStrangerTag), isNull);
    },
  );

  group('the provider', () {
    ProviderContainer container(ServerProfile? profile) {
      final c = ProviderContainer(overrides: [serverProfileOverride(profile)]);
      addTearDown(c.dispose);
      return c;
    }

    test('is the demo reader on the demo server', () {
      final c = container(
        const ServerProfile(
          baseUrl: DemoConfig.baseUrl,
          authMode: AuthMode.none,
        ),
      );

      expect(c.read(nfcReaderProvider), isA<DemoNfcReader>());
    });

    test('is the phone\'s on any other', () {
      final c = container(
        const ServerProfile(
          baseUrl: fakeServerBaseUrl,
          authMode: AuthMode.none,
        ),
      );

      expect(c.read(nfcReaderProvider), isA<ChannelNfcReader>());
    });
  });

  testWidgets(
    'the demo scanner shows the switch, then the stranger, then opens a spool',
    (tester) async {
      SharedPreferences.setMockInitialValues({'spool_scan_nfc': true});
      final prefs = await SharedPreferences.getInstance();
      final dio = Dio(BaseOptions(baseUrl: DemoConfig.baseUrl))
        ..httpClientAdapter = DemoHttpClientAdapter(
          DemoBackend.instance.handle,
          latency: Duration.zero,
        );
      final spools = await tester.runAsync(
        () => NativeInventorySource(dio).fetchSpools(),
      );
      int? scanned;
      await tester.pumpWidget(
        ProviderScope(
          retry: neverRetry,
          overrides: [
            serverProfileOverride(
              const ServerProfile(
                baseUrl: DemoConfig.baseUrl,
                authMode: AuthMode.none,
              ),
            ),
            inventoryProvider.overrideWith(
              () => _Shelf(InventoryState(spools: spools!)),
            ),
            sharedPreferencesProvider.overrideWithValue(prefs),
          ],
          child: plApp(
            Builder(
              builder: (context) => TextButton(
                onPressed: () async =>
                    scanned = await Navigator.of(context).push<int>(
                      MaterialPageRoute(
                        builder: (_) => const SpoolScannerScreen(),
                      ),
                    ),
                child: const Text('scan'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('scan'));
      // The route opens, then the phone answers what NFC is.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 100));

      expect(byLogId('spool_scan.mode'), findsOneWidget);
      expect(find.text(pl.spoolScanNfcHint), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(find.text(pl.spoolScanTagUnknown), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(
        scanned,
        spools!.firstWhere((s) => s.tagUid == demoNfcSpoolTag).id,
      );
    },
  );

  testWidgets('the demo reader leaves no timer behind when its listener goes', (
    tester,
  ) async {
    const reader = DemoNfcReader();
    final heard = <String>[];
    final subscription = reader.tags().listen(heard.add);

    await tester.pump(const Duration(seconds: 1));
    // Fire and forget: a timer still running would fail the test at its end.
    unawaited(subscription.cancel());
    await tester.pump();

    expect(heard, isEmpty);
  });

  testWidgets('and the stranger comes first, then the spool, then it ends', (
    tester,
  ) async {
    const reader = DemoNfcReader();
    final heard = <String>[];
    var done = false;
    reader.tags().listen(heard.add, onDone: () => done = true);

    await tester.pump(const Duration(seconds: 3));
    expect(heard, [demoNfcStrangerTag]);
    await tester.pump(const Duration(seconds: 3));
    expect(heard, [demoNfcStrangerTag, demoNfcSpoolTag]);
    await tester.pump();
    expect(done, isTrue);
  });
}

/// The demo's shelf, which a reload leaves as it is.
class _Shelf extends InventoryNotifier {
  _Shelf(this._state);

  final InventoryState _state;

  @override
  Future<InventoryState> build() async => _state;

  @override
  Future<void> refresh({bool askBackend = false}) async {}
}
