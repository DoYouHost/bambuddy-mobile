import 'dart:async';

import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/core/nfc/nfc_reader.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_providers.dart';
import 'package:bambuddy_mobile/features/inventory/spool_scanner_screen.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

/// The spool scanner's NFC side (#71): the camera | NFC switch, the side that is
/// remembered, and what a tag held to the phone does.
void main() {
  const tagA = '04A1B2C3D4E5F6';
  const red = Spool(
    id: 7,
    material: 'PLA',
    subtype: 'Basic',
    colorName: 'Red',
    brand: 'Bambu Lab',
    labelWeight: 1000,
    tagUid: tagA,
  );

  // The camera plugin: answered "refused", which is all the screen needs to
  // draw. Every call it gets is kept, to see whether the camera was touched.
  const scanner = MethodChannel(
    'dev.steenbakker.mobile_scanner/scanner/method',
  );
  const eventChannels = [
    MethodChannel('dev.steenbakker.mobile_scanner/scanner/event'),
    MethodChannel('dev.steenbakker.mobile_scanner/scanner/deviceOrientation'),
  ];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<String> cameraCalls;

  setUp(() {
    cameraCalls = [];
    messenger.setMockMethodCallHandler(scanner, (call) async {
      cameraCalls.add(call.method);
      return call.method == 'state' ? 2 : false;
    });
    for (final channel in eventChannels) {
      messenger.setMockMethodCallHandler(channel, (_) async => null);
    }
  });

  tearDown(() {
    for (final channel in [scanner, ...eventChannels]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });

  late _Nfc nfc;
  late _Shelf shelf;
  late SharedPreferences prefs;
  int? scanned;
  var popped = false;

  /// The scanner pushed from a button, as a caller does, with what it returned.
  Future<void> open(
    WidgetTester tester, {
    NfcStatus status = NfcStatus.ready,
    bool remembered = false,
    InventoryState? inventory,
    double scale = 1,
    Completer<void>? buildHold,
  }) async {
    SharedPreferences.setMockInitialValues({
      if (remembered) 'spool_scan_nfc': true,
    });
    prefs = await SharedPreferences.getInstance();
    nfc = _Nfc(status);
    shelf = _Shelf(inventory ?? InventoryState(spools: const [red]))
      ..buildHold = buildHold;
    scanned = null;
    popped = false;
    await tester.pumpWidget(
      ProviderScope(
        retry: neverRetry,
        overrides: [
          nfcReaderProvider.overrideWithValue(nfc),
          inventoryProvider.overrideWith(() => shelf),
          sharedPreferencesProvider.overrideWithValue(prefs),
          noServerProfileOverride,
        ],
        child: plApp(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  scanned = await Navigator.of(context).push<int>(
                    MaterialPageRoute(
                      builder: (_) => const SpoolScannerScreen(),
                    ),
                  );
                  popped = true;
                },
                child: const Text('scan'),
              ),
            ),
          ),
          builder: textScaled(scale),
        ),
      ),
    );
    await tester.tap(find.text('scan'));
    await tester.pumpAndSettle();
  }

  group('the switch', () {
    testWidgets(
      'is absent on a phone without NFC, and the title is as before',
      (tester) async {
        await open(tester, status: NfcStatus.unsupported);

        expect(byLogId('spool_scan.mode'), findsNothing);
        expect(find.text(pl.inventoryScanTitle), findsOneWidget);
      },
    );

    testWidgets('opens on the camera, and NFC is a tap away', (tester) async {
      await open(tester);

      expect(byLogId('spool_scan.mode'), findsOneWidget);
      expect(find.text(pl.spoolScanTitle), findsOneWidget);
      expect(find.text(pl.spoolScanNfcHint), findsNothing);

      await tester.tap(find.text(pl.spoolScanModeNfc));
      await tester.pumpAndSettle();

      expect(find.text(pl.spoolScanNfcHint), findsOneWidget);
      expect(prefs.getBool('spool_scan_nfc'), isTrue);
    });

    testWidgets('and back to the camera, which is remembered too', (
      tester,
    ) async {
      await open(tester, remembered: true);

      await tester.tap(find.text(pl.spoolScanModeCamera));
      await tester.pumpAndSettle();

      expect(find.text(pl.spoolScanNfcHint), findsNothing);
      expect(prefs.getBool('spool_scan_nfc'), isFalse);
    });

    testWidgets(
      'opens on NFC when that was the side used last, camera untouched',
      (tester) async {
        await open(tester, remembered: true);

        expect(find.text(pl.spoolScanNfcHint), findsOneWidget);
        expect(cameraCalls, isEmpty);
      },
    );

    testWidgets(
      'a remembered NFC on a phone that has none falls to the camera',
      (tester) async {
        await open(tester, status: NfcStatus.unsupported, remembered: true);

        expect(find.text(pl.spoolScanNfcHint), findsNothing);
        expect(find.text(pl.inventoryScanTitle), findsOneWidget);
        expect(
          prefs.getBool('spool_scan_nfc'),
          isTrue,
          reason: 'the choice stays for a phone that has NFC',
        );
      },
    );
  });

  group('a tag', () {
    testWidgets('of a known spool closes the scanner with its id', (
      tester,
    ) async {
      await open(tester, remembered: true);

      nfc.read(tagA);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(popped, isTrue);
      expect(scanned, 7);
      expect(find.text(pl.spoolScanOpening(red.displayName)), findsWidgets);
    });

    testWidgets('that no spool has says which one, and keeps waiting', (
      tester,
    ) async {
      await open(tester, remembered: true);

      nfc.read('04FFFFFFFFFFFF');
      await tester.pumpAndSettle();

      expect(popped, isFalse);
      expect(find.text(pl.spoolScanTagUnknown), findsOneWidget);
      expect(
        find.text(pl.spoolScanTagUnknownHelp('04FFFFFFFFFFFF')),
        findsOneWidget,
      );

      nfc.read(tagA);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(scanned, 7, reason: 'the next tag is read as the first was');
    });

    testWidgets('linked a moment ago is found after one reload of the shelf', (
      tester,
    ) async {
      await open(tester, remembered: true, inventory: InventoryState());
      shelf.onRefresh = InventoryState(spools: const [red]);

      nfc.read(tagA);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(shelf.refreshes, 1);
      expect(scanned, 7);
    });

    testWidgets(
      'unknown asks the shelf once, and a second at once is ignored',
      (tester) async {
        await open(tester, remembered: true);
        shelf.hold = Completer<void>();

        nfc.read('04FFFFFFFFFFFF');
        nfc.read('04EEEEEEEEEEEE');
        await tester.pump();
        shelf.hold!.complete();
        await tester.pumpAndSettle();

        expect(shelf.refreshes, 1);
        expect(
          find.text(pl.spoolScanTagUnknownHelp('04FFFFFFFFFFFF')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'read when the shelf cannot be loaded says why, not "unknown"',
      (tester) async {
        await open(tester, remembered: true, inventory: InventoryState());
        shelf.failOnRefresh = true;

        nfc.read('04FFFFFFFFFFFF');
        await tester.pumpAndSettle();

        expect(find.text(pl.spoolScanTagUnknown), findsNothing);
        expect(popped, isFalse);
      },
    );

    testWidgets(
      'a second one while the scanner is closing does not pop again',
      (tester) async {
        await open(tester, remembered: true);

        nfc.read(tagA);
        await tester.pump();
        nfc.read(tagA);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();

        expect(scanned, 7);
        expect(
          find.text('scan'),
          findsOneWidget,
          reason: 'the caller is still there',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('read while the shelf is still loading waits for it', (
      tester,
    ) async {
      final load = Completer<void>();
      await open(tester, remembered: true, buildHold: load);

      nfc.read(tagA);
      await tester.pump();
      expect(shelf.refreshes, 0);
      load.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(shelf.refreshes, 0, reason: 'the load in flight was the read');
      expect(scanned, 7);
    });

    testWidgets('read while loading, then backed out of, closes nothing more', (
      tester,
    ) async {
      final load = Completer<void>();
      await open(tester, remembered: true, buildHold: load);

      nfc.read(tagA);
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 50));
      load.complete();
      await tester.pumpAndSettle();

      expect(scanned, isNull, reason: 'it was backed out of, not scanned');
      expect(
        find.text('scan'),
        findsOneWidget,
        reason: 'the caller is still there',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'a shelf that fails with a bug surfaces it and leaves the screen',
      (tester) async {
        await open(tester, remembered: true, inventory: InventoryState());
        shelf.bugOnRefresh = true;

        nfc.read('04FFFFFFFFFFFF');
        await tester.pumpAndSettle();

        expect(tester.takeException(), isA<StateError>());
        expect(find.text(pl.spoolScanNfcHint), findsOneWidget);
      },
    );

    for (final scale in const [1.0, 1.5, 2.0]) {
      testWidgets('the longest message fits, at $scale text', (tester) async {
        await open(tester, remembered: true, scale: scale);

        nfc.read('04FFFFFFFFFFFF');
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(byLogId('spool_scan.mode'), findsOneWidget);
      });
    }
  });

  group('NFC switched off', () {
    testWidgets('says so and opens the system settings', (tester) async {
      await open(tester, status: NfcStatus.disabled, remembered: true);

      expect(find.text(pl.spoolScanNfcOff), findsOneWidget);
      expect(nfc.listening, isFalse);

      await tester.tap(byLogId('spool_scan.nfc_settings'));
      await tester.pump();

      expect(nfc.settingsOpened, 1);
    });

    testWidgets('coming back with it on starts reading', (tester) async {
      await open(tester, status: NfcStatus.disabled, remembered: true);

      nfc.current = NfcStatus.ready;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.text(pl.spoolScanNfcHint), findsOneWidget);
      nfc.read(tagA);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(scanned, 7);
    });

    testWidgets('going off while reading is noticed', (tester) async {
      await open(tester, remembered: true);

      nfc.current = NfcStatus.disabled;
      nfc.fail(PlatformException(code: 'nfc_unavailable'));
      await tester.pumpAndSettle();

      expect(find.text(pl.spoolScanNfcOff), findsOneWidget);
      expect(nfc.listening, isFalse, reason: 'reading stops while it is off');
    });
  });

  testWidgets(
    'a failure of the reader that is not "off" is a bug and surfaces',
    (tester) async {
      await open(tester, remembered: true);

      nfc.fail(StateError('the reader broke'));
      await tester.pump();

      expect(tester.takeException(), isA<StateError>());
    },
  );

  testWidgets('leaving the screen stops the reading', (tester) async {
    await open(tester, remembered: true);
    expect(nfc.listening, isTrue);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(nfc.listening, isFalse);
  });
}

/// A phone's NFC the test drives.
class _Nfc implements NfcReader {
  _Nfc(this.current);

  NfcStatus current;
  int settingsOpened = 0;
  final _controller = StreamController<String>.broadcast();

  bool get listening => _controller.hasListener;

  void read(String uid) => _controller.add(uid);

  void fail(Object error) => _controller.addError(error);

  @override
  Future<NfcStatus> status() async => current;

  @override
  Future<void> openSettings() async => settingsOpened++;

  @override
  Stream<String> tags() => _controller.stream;
}

/// A shelf that can change under the scanner, and counts how often it is asked
/// to reload.
class _Shelf extends InventoryNotifier {
  _Shelf(this._state);

  final InventoryState _state;
  int refreshes = 0;

  /// What the next reload brings.
  InventoryState? onRefresh;

  /// Holds a reload until it is completed.
  Completer<void>? hold;
  bool failOnRefresh = false;

  /// A reload that fails with something that is not the server's refusal.
  bool bugOnRefresh = false;

  /// Holds the first load until it is completed.
  Completer<void>? buildHold;

  @override
  Future<InventoryState> build() async {
    await buildHold?.future;
    return _state;
  }

  @override
  Future<void> refresh({bool askBackend = false}) async {
    refreshes++;
    await hold?.future;
    if (bugOnRefresh) {
      state = AsyncError<InventoryState>(
        StateError('shelf bug'),
        StackTrace.empty,
      );
      return;
    }
    if (failOnRefresh) {
      state = AsyncError<InventoryState>(
        const ApiException(AppErrorCode.connectionError),
        StackTrace.empty,
      );
      return;
    }
    state = AsyncData(onRefresh ?? _state);
  }
}
