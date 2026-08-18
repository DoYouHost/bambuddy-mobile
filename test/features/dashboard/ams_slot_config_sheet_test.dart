import 'package:bambuddy_mobile/core/ams/slot_configuration.dart';
import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/ams_filament_preset.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/data/ams_slot_config_repository.dart';
import 'package:bambuddy_mobile/features/dashboard/widgets/ams_slot_config_sheet.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

class _FakeProfileNotifier extends ServerProfileNotifier {
  @override
  ServerProfile? build() => const ServerProfile(
        baseUrl: 'http://s.local:8000',
        authMode: AuthMode.none,
      );
}

class _ApiKeyProfileNotifier extends ServerProfileNotifier {
  @override
  ServerProfile? build() => const ServerProfile(
        baseUrl: 'http://s.local:8000',
        authMode: AuthMode.apiKey,
      );
}

/// Records what the sheet writes and can be told to withhold each source.
class _FakeRepo implements AmsSlotConfigRepository {
  final List<String> calls = [];
  Object? cloudError;
  Object? saveError;

  /// Overrides the cloud tier, for the printer-filter tests.
  List<AmsFilamentPreset>? cloudPresets;
  SlotConfiguration? written;
  String? cloudDetailId;

  @override
  Future<List<AmsFilamentPreset>> cloudFilaments() async {
    if (cloudError != null) throw cloudError!;
    if (cloudPresets != null) return cloudPresets!;
    return const [
      AmsFilamentPreset(
        source: AmsPresetSource.cloud,
        id: 'GFSL05_09',
        name: 'Bambu PLA Basic',
      ),
    ];
  }

  @override
  Future<List<AmsFilamentPreset>> localFilaments() async => const [
        AmsFilamentPreset(
          source: AmsPresetSource.local,
          id: '7',
          name: 'eSUN PETG',
          filamentType: 'PETG',
        ),
      ];

  @override
  Future<List<AmsFilamentPreset>> builtinFilaments() async => const [
        AmsFilamentPreset(
          source: AmsPresetSource.builtin,
          id: 'GFL99',
          name: 'Generic PLA',
        ),
      ];

  @override
  Future<Map<String, String>> printerModels() async =>
      const {'Bambu Lab X1 Carbon': 'X1C'};

  /// What the server remembers for the slot — stale on purpose in one test.
  SlotPreset? saved;

  @override
  Future<SlotPreset?> slotPreset(int printerId,
          {required int amsId, required int trayId}) async =>
      saved;

  @override
  Future<String?> cloudFilamentId(String settingId) async {
    cloudDetailId = settingId;
    return 'P285e239';
  }

  @override
  Future<void> configureSlot(int printerId,
      {required int amsId,
      required int trayId,
      required SlotConfiguration configuration}) async {
    calls.add('configure:$printerId:$amsId:$trayId');
    written = configuration;
  }

  @override
  Future<void> saveSlotPreset(int printerId,
      {required int amsId,
      required int trayId,
      required AmsFilamentPreset preset,
      required String presetName}) async {
    calls.add('save:${preset.pickerId}:$presetName');
    if (saveError != null) throw saveError!;
  }

  @override
  Future<void> resetSlot(int printerId,
      {required int amsId, required int trayId}) async {
    calls.add('reset:$printerId:$amsId:$trayId');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not part of this test');
}

void main() {
  // A phone, not the 800x600 default: the sheet is 75% of the window with a
  // pinned action bar, so on the default surface almost no list rows are built
  // and the tests would be measuring the test window rather than the sheet.
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher
        .implicitView!;
    view.physicalSize = const Size(1080, 2400);
    view.devicePixelRatio = 3.0;
    addTearDown(() {
      view.resetPhysicalSize();
      view.resetDevicePixelRatio();
    });
  });

  const target = AmsSlotTarget(
    printerId: 1,
    amsId: 0,
    trayId: 2,
    label: 'AMS 1 · 3',
    printerModel: 'X1C',
    nozzleDiameter: '0.6',
    currentColour: '0ACC38FF',
  );

  /// Opens the sheet the way the card does — as a modal route over a host
  /// screen. Nothing else gives the sheet a route to pop or a Scaffold to show
  /// its result on, which is half of what these tests are checking.
  Future<_FakeRepo> openSheet(WidgetTester tester, {_FakeRepo? repo}) async {
    final fake = repo ?? _FakeRepo();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        serverProfileProvider.overrideWith(_FakeProfileNotifier.new),
        amsSlotConfigRepositoryProvider.overrideWithValue(fake),
      ],
      child: plApp(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => const AmsSlotConfigSheet(target: target),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return fake;
  }

  /// The sheet is a lazily-built list inside a 75%-height panel, so anything
  /// past the first screenful is not in the tree at all until scrolled to.
  Future<Finder> scrollTo(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        finder,
        120,
        scrollable: find
            .descendant(
              of: find.byType(AmsSlotConfigSheet),
              matching: find.byType(Scrollable),
            )
            .first,
      );
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    return finder;
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await scrollTo(tester, finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('lists every tier, imported first', (tester) async {
    await openSheet(tester);

    final names = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .toList();

    expect(names, containsAll(['eSUN PETG', 'Bambu PLA Basic']));
    expect(names.indexOf('eSUN PETG'), lessThan(names.indexOf('Bambu PLA Basic')),
        reason: 'imported presets outrank the cloud');
    await scrollTo(tester, find.text('Generic PLA'));
    expect(find.text('Generic PLA'), findsOneWidget,
        reason: 'the built-in table is the floor, below both');
  });

  testWidgets('scrolling the list leaves the form and the actions in place',
      (tester) async {
    // The list runs to hundreds of rows; scrolling it must not carry away the
    // colour field, the search or the buttons.
    await openSheet(tester);
    await scrollTo(tester, find.text('Generic PLA'));

    expect(find.text('Szukaj presetu'), findsOneWidget);
    expect(find.text('Kolor'), findsOneWidget);
    expect(find.text('Zapisz w drukarce'), findsOneWidget);
    expect(find.text('Wyczyść slot'), findsOneWidget);
  });

  testWidgets('writes the picked preset and remembers it', (tester) async {
    final repo = await openSheet(tester);

    await tapVisible(tester, find.text('Generic PLA'));
    await tapVisible(tester, find.text('Zapisz w drukarce'));

    expect(repo.calls, ['configure:1:0:2', 'save:builtin_GFL99:Generic PLA']);
    final written = repo.written!;
    expect(written.trayInfoIdx, 'GFL99');
    expect(written.trayType, 'PLA');
    expect(written.nozzleDiameter, '0.6',
        reason: 'the nozzle the slot feeds, not the 0.4 default');
    expect(written.trayColour, '0ACC38FF',
        reason: "starts from the slot's current colour");
  });

  testWidgets('a user cloud preset travels with the id from its detail',
      (tester) async {
    // Deriving it from the setting id would resolve the slot to the generic
    // the preset inherits from (bambuddy #1053).
    final repo = await openSheet(tester);

    await tapVisible(tester, find.text('Bambu PLA Basic'));
    await tapVisible(tester, find.text('Zapisz w drukarce'));

    expect(repo.cloudDetailId, 'GFSL05_09');
    expect(repo.written!.trayInfoIdx, 'P285e239');
    expect(repo.written!.settingId, 'GFSL05_09');
  });

  testWidgets('a refused mapping save is reported, not swallowed',
      (tester) async {
    // The filament is set, so the write did not fail — but the server kept the
    // *previous* preset name, which is what the sheet will show next time. A
    // silent success there reads as "the app forgot what I picked".
    final repo = _FakeRepo()
      ..saveError = const AuthException(AppErrorCode.forbidden);
    await openSheet(tester, repo: repo);

    await tapVisible(tester, find.text('Generic PLA'));
    await tapVisible(tester, find.text('Zapisz w drukarce'));

    expect(repo.calls, ['configure:1:0:2', 'save:builtin_GFL99:Generic PLA']);
    expect(find.textContaining('nazwy presetu nie udało się zapisać'),
        findsOneWidget);
  });

  testWidgets('a stale mapping does not win over the loaded filament',
      (tester) async {
    // Exactly the shape a refused save leaves behind: the server still names
    // the preset the slot had before. The printer's own filament id is the
    // authority, and it says ABS.
    final repo = _FakeRepo()
      ..saved = const SlotPreset(
        amsId: 0,
        trayId: 2,
        presetId: 'GFSL99_01',
        presetName: 'Bambu PLA (stary)',
      )
      ..cloudPresets = [
        const AmsFilamentPreset(
          source: AmsPresetSource.cloud,
          id: 'GFSB00_04',
          name: 'Bambu ABS @BBL X1C',
        ),
      ];

    await tester.pumpWidget(ProviderScope(
      overrides: [
        serverProfileProvider.overrideWith(_FakeProfileNotifier.new),
        amsSlotConfigRepositoryProvider.overrideWithValue(repo),
      ],
      child: plApp(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => const AmsSlotConfigSheet(
                  target: AmsSlotTarget(
                    printerId: 1,
                    amsId: 0,
                    trayId: 2,
                    label: 'AMS 1 · 3',
                    printerModel: 'X1C',
                    currentFilamentId: 'GFB00',
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Nothing was tapped, so a preselection is the only thing that can arm the
    // button — and it must be the ABS the printer reports.
    await scrollTo(tester, find.text('Zapisz w drukarce'));
    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Zapisz w drukarce'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(button.onPressed, isNotNull);

    await tapVisible(tester, find.text('Zapisz w drukarce'));
    expect(repo.calls, contains('save:GFSB00_04:Bambu ABS'),
        reason: 'the ABS the printer reports, not the PLA the server remembers');
    expect(repo.written!.trayType, 'ABS');
  });

  testWidgets('an API key does not even try to save the preset name',
      (tester) async {
    // bambuddy denies `printers:update` to every API key whatever scopes it
    // was created with (`core/auth.py`, `_APIKEY_DENIED_PERMISSIONS`), so the
    // PUT is a guaranteed 403 — and a warning after every single save that the
    // user cannot act on.
    final repo = _FakeRepo();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        serverProfileProvider.overrideWith(_ApiKeyProfileNotifier.new),
        amsSlotConfigRepositoryProvider.overrideWithValue(repo),
      ],
      child: plApp(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => const AmsSlotConfigSheet(target: target),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tapVisible(tester, find.text('Generic PLA'));
    await tapVisible(tester, find.text('Zapisz w drukarce'));

    expect(repo.calls, ['configure:1:0:2'], reason: 'no doomed PUT');
    expect(find.textContaining('nazwy presetu nie udało się zapisać'),
        findsNothing);
    expect(find.text('Konfigurowanie slotu…'), findsOneWidget);
  });

  testWidgets('what the slot is set to sits at the top, labelled',
      (tester) async {
    // Alphabetically "Generic PLA" is last of the three; as the slot's current
    // filament it has to be the first thing the sheet shows.
    final repo = _FakeRepo()
      ..saved = const SlotPreset(
        amsId: 0,
        trayId: 2,
        presetId: 'builtin_GFL99',
        presetName: 'Generic PLA',
      );
    await openSheet(tester, repo: repo);

    expect(find.text('Generic PLA'), findsOneWidget,
        reason: 'on screen without scrolling');
    expect(find.textContaining('Ustawiony teraz'), findsOneWidget);

    final rows = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .toList();
    expect(rows.indexOf('Generic PLA'), lessThan(rows.indexOf('eSUN PETG')),
        reason: 'above the tier order it would otherwise sit under');
  });

  testWidgets('the pinned row does not move when another preset is tapped',
      (tester) async {
    // Re-sorting on every tap would slide the list out from under the finger.
    final repo = _FakeRepo()
      ..saved = const SlotPreset(
        amsId: 0,
        trayId: 2,
        presetId: 'builtin_GFL99',
        presetName: 'Generic PLA',
      );
    await openSheet(tester, repo: repo);

    await tapVisible(tester, find.text('eSUN PETG'));

    final rows = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .toList();
    expect(rows.indexOf('Generic PLA'), lessThan(rows.indexOf('eSUN PETG')));
  });

  testWidgets('the write waits for a preset to be picked', (tester) async {
    await openSheet(tester);
    await scrollTo(tester, find.text('Zapisz w drukarce'));

    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Zapisz w drukarce'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('reset asks before clearing the slot', (tester) async {
    final repo = await openSheet(tester);

    await tapVisible(tester, find.text('Wyczyść slot'));
    expect(find.text('Wyczyścić slot?'), findsOneWidget);

    await tester.tap(find.text('Anuluj'));
    await tester.pumpAndSettle();
    expect(repo.calls, isEmpty, reason: 'a cancelled confirmation sends nothing');

    await tapVisible(tester, find.text('Wyczyść slot'));
    // The dialog's own confirm button carries the same label as the opener.
    await tester.tap(find.text('Wyczyść slot').last);
    await tester.pumpAndSettle();

    expect(repo.calls, ['reset:1:0:2']);
  });

  group('printer filter', () {
    AmsFilamentPreset cloud(String id, String name) => AmsFilamentPreset(
          source: AmsPresetSource.cloud,
          id: id,
          name: name,
        );

    Future<_FakeRepo> openWith(
      WidgetTester tester, {
      required String? printerModel,
    }) async {
      final repo = _FakeRepo()
        ..cloudPresets = [
          cloud('GFSB99', 'Bambu ABS @BBL X1C'),
          cloud('GFSB98', 'Bambu ASA @BBL A1'),
          cloud('GFSB97', 'Bambu ABS @BBL H2C 0.2 nozzle'),
        ];
      await tester.pumpWidget(ProviderScope(
        overrides: [
          serverProfileProvider.overrideWith(_FakeProfileNotifier.new),
          amsSlotConfigRepositoryProvider.overrideWithValue(repo),
        ],
        child: plApp(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => AmsSlotConfigSheet(
                    target: AmsSlotTarget(
                      printerId: 1,
                      amsId: 0,
                      trayId: 2,
                      label: 'AMS 1 · 3',
                      printerModel: printerModel,
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return repo;
    }

    testWidgets('hides presets that name another printer', (tester) async {
      await openWith(tester, printerModel: 'X1C');

      // The count is the assertion that the other two are gone: a lazily-built
      // list has no element for an off-screen row either, so `findsNothing`
      // would pass whether they were filtered or merely scrolled past.
      expect(find.text('Tylko dla X1C (ukryto 2)'), findsOneWidget);
      await scrollTo(tester, find.text('Bambu ABS @BBL X1C'));
      expect(find.text('Bambu ABS @BBL X1C'), findsOneWidget);
    });

    testWidgets('says how many it is hiding, and shows them on demand',
        (tester) async {
      // The count is the only honest label for a switch that turns a filter
      // off — "show all" alone says nothing about what is missing.
      await openWith(tester, printerModel: 'X1C');
      expect(find.text('Tylko dla X1C (ukryto 2)'), findsOneWidget);

      await tapVisible(tester, find.text('Tylko dla X1C (ukryto 2)'));

      expect(find.text('Tylko dla X1C'), findsOneWidget,
          reason: 'nothing is hidden any more, so the count goes away');
      await scrollTo(tester, find.text('Bambu ASA @BBL A1'));
      expect(find.text('Bambu ASA @BBL A1'), findsOneWidget);
    });

    testWidgets('an unknown printer model is said out loud, not filtered on',
        (tester) async {
      // Otherwise an unfiltered list looks exactly like a filter that does
      // nothing, and there is no way to tell which one it is.
      await openWith(tester, printerModel: null);

      expect(find.textContaining('Nieznany model drukarki'), findsOneWidget);
      await scrollTo(tester, find.text('Bambu ASA @BBL A1'));
      expect(find.text('Bambu ASA @BBL A1'), findsOneWidget);
    });
  });

  testWidgets('offers a cloud login when that is why the tier is missing',
      (tester) async {
    final repo = _FakeRepo()
      ..cloudError = const AuthException(AppErrorCode.unauthorized);
    await openSheet(tester, repo: repo);

    expect(find.textContaining('Zaloguj się do Bambu Cloud'), findsOneWidget);
    await scrollTo(tester, find.text('Generic PLA'));
    expect(find.text('Generic PLA'), findsOneWidget,
        reason: 'the other tiers still fill the picker');
  });
}
