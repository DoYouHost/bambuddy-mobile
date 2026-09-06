import 'package:bambuddy_mobile/core/ams/slot_configuration.dart';
import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/ams_filament_preset.dart';
import 'package:bambuddy_mobile/core/models/inventory_reference.dart';
import 'package:bambuddy_mobile/core/models/k_profile.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_providers.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/data/ams_slot_config_repository.dart';
import 'package:bambuddy_mobile/features/dashboard/widgets/ams_slot_config_sheet.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

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
  Future<Map<String, String>> printerModels() async => const {
    'Bambu Lab X1 Carbon': 'X1C',
  };

  /// The printer's calibration table, and the nozzle it was asked about.
  List<KProfile> profiles = const [];
  String? profilesNozzle;

  Object? profilesError;

  @override
  Future<List<KProfile>> kProfiles(
    int printerId, {
    required String nozzleDiameter,
  }) async {
    profilesNozzle = nozzleDiameter;
    if (profilesError != null) throw profilesError!;
    return profiles;
  }

  /// What the server remembers for the slot — stale on purpose in one test.
  SlotPreset? saved;

  @override
  Future<SlotPreset?> slotPreset(
    int printerId, {
    required int amsId,
    required int trayId,
  }) async => saved;

  @override
  Future<String?> cloudFilamentId(String settingId) async {
    cloudDetailId = settingId;
    return 'P285e239';
  }

  @override
  Future<void> configureSlot(
    int printerId, {
    required int amsId,
    required int trayId,
    required SlotConfiguration configuration,
  }) async {
    calls.add('configure:$printerId:$amsId:$trayId');
    written = configuration;
  }

  @override
  Future<void> saveSlotPreset(
    int printerId, {
    required int amsId,
    required int trayId,
    required AmsFilamentPreset preset,
    required String presetName,
  }) async {
    calls.add('save:${preset.pickerId}:$presetName');
    if (saveError != null) throw saveError!;
  }

  @override
  Future<void> resetSlot(
    int printerId, {
    required int amsId,
    required int trayId,
  }) async {
    calls.add('reset:$printerId:$amsId:$trayId');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '${invocation.memberName} is not part of this test',
  );
}

void main() {
  // A phone, not the 800x600 default: the sheet is 75% of the window with a
  // pinned action bar, so on the default surface almost no list rows are built
  // and the tests would be measuring the test window rather than the sheet.
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
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
  Future<_FakeRepo> openSheet(
    WidgetTester tester, {
    _FakeRepo? repo,
    AmsSlotTarget? slot,
    List<ColorEntry>? colours,
  }) async {
    final fake = repo ?? _FakeRepo();
    await pumpPhone(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => AmsSlotConfigSheet(target: slot ?? target),
            ),
            child: const Text('open'),
          ),
        ),
      ),
      overrides: [
        fakeServerProfileOverride(),
        amsSlotConfigRepositoryProvider.overrideWithValue(fake),
        colorCatalogProvider.overrideWith((ref) async => colours ?? const []),
      ],
    );
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
    expect(
      names.indexOf('eSUN PETG'),
      lessThan(names.indexOf('Bambu PLA Basic')),
      reason: 'imported presets outrank the cloud',
    );
    await scrollTo(tester, find.text('Generic PLA'));
    expect(
      find.text('Generic PLA'),
      findsOneWidget,
      reason: 'the built-in table is the floor, below both',
    );
  });

  testWidgets('scrolling the list leaves the form and the actions in place', (
    tester,
  ) async {
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
    expect(
      written.nozzleDiameter,
      '0.6',
      reason: 'the nozzle the slot feeds, not the 0.4 default',
    );
    expect(
      written.trayColour,
      '0ACC38FF',
      reason: "starts from the slot's current colour",
    );
  });

  testWidgets('a user cloud preset travels with the id from its detail', (
    tester,
  ) async {
    // Deriving it from the setting id would resolve the slot to the generic
    // the preset inherits from (bambuddy #1053).
    final repo = await openSheet(tester);

    await tapVisible(tester, find.text('Bambu PLA Basic'));
    await tapVisible(tester, find.text('Zapisz w drukarce'));

    expect(repo.cloudDetailId, 'GFSL05_09');
    expect(repo.written!.trayInfoIdx, 'P285e239');
    expect(repo.written!.settingId, 'GFSL05_09');
  });

  testWidgets('a refused mapping save is reported, not swallowed', (
    tester,
  ) async {
    // The filament is set, so the write did not fail — but the server kept the
    // *previous* preset name, which is what the sheet will show next time. A
    // silent success there reads as "the app forgot what I picked".
    final repo = _FakeRepo()
      ..saveError = const AuthException(AppErrorCode.forbidden);
    await openSheet(tester, repo: repo);

    await tapVisible(tester, find.text('Generic PLA'));
    await tapVisible(tester, find.text('Zapisz w drukarce'));

    expect(repo.calls, ['configure:1:0:2', 'save:builtin_GFL99:Generic PLA']);
    expect(
      find.textContaining('nazwy presetu nie udało się zapisać'),
      findsOneWidget,
    );
  });

  testWidgets('a stale mapping does not win over the loaded filament', (
    tester,
  ) async {
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

    await pumpPhone(
      tester,
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
      overrides: [
        fakeServerProfileOverride(),
        amsSlotConfigRepositoryProvider.overrideWithValue(repo),
      ],
    );
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
    expect(
      repo.calls,
      contains('save:GFSB00_04:Bambu ABS'),
      reason: 'the ABS the printer reports, not the PLA the server remembers',
    );
    expect(repo.written!.trayType, 'ABS');
  });

  testWidgets('an API key does not even try to save the preset name', (
    tester,
  ) async {
    // bambuddy denies `printers:update` to every API key whatever scopes it
    // was created with (`core/auth.py`, `_APIKEY_DENIED_PERMISSIONS`), so the
    // PUT is a guaranteed 403 — and a warning after every single save that the
    // user cannot act on.
    final repo = _FakeRepo();
    await pumpPhone(
      tester,
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
      overrides: [
        fakeServerProfileOverride(authMode: AuthMode.apiKey),
        amsSlotConfigRepositoryProvider.overrideWithValue(repo),
      ],
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tapVisible(tester, find.text('Generic PLA'));
    await tapVisible(tester, find.text('Zapisz w drukarce'));

    expect(repo.calls, ['configure:1:0:2'], reason: 'no doomed PUT');
    expect(
      find.textContaining('nazwy presetu nie udało się zapisać'),
      findsNothing,
    );
    expect(find.text('Konfigurowanie slotu…'), findsOneWidget);
  });

  testWidgets('what the slot is set to sits at the top, labelled', (
    tester,
  ) async {
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

    expect(
      find.text('Generic PLA'),
      findsOneWidget,
      reason: 'on screen without scrolling',
    );
    expect(find.textContaining('Ustawiony teraz'), findsOneWidget);

    final rows = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .toList();
    expect(
      rows.indexOf('Generic PLA'),
      lessThan(rows.indexOf('eSUN PETG')),
      reason: 'above the tier order it would otherwise sit under',
    );
  });

  testWidgets('the pinned row does not move when another preset is tapped', (
    tester,
  ) async {
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
    expect(
      repo.calls,
      isEmpty,
      reason: 'a cancelled confirmation sends nothing',
    );

    await tapVisible(tester, find.text('Wyczyść slot'));
    // The dialog's own confirm button carries the same label as the opener.
    await tester.tap(find.text('Wyczyść slot').last);
    await tester.pumpAndSettle();

    expect(repo.calls, ['reset:1:0:2']);
  });

  group('printer filter', () {
    AmsFilamentPreset cloud(String id, String name) =>
        AmsFilamentPreset(source: AmsPresetSource.cloud, id: id, name: name);

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
      await pumpPhone(
        tester,
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
        overrides: [
          fakeServerProfileOverride(),
          amsSlotConfigRepositoryProvider.overrideWithValue(repo),
        ],
      );
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

    testWidgets('says how many it is hiding, and shows them on demand', (
      tester,
    ) async {
      // The count is the only honest label for a switch that turns a filter
      // off — "show all" alone says nothing about what is missing.
      await openWith(tester, printerModel: 'X1C');
      expect(find.text('Tylko dla X1C (ukryto 2)'), findsOneWidget);

      await tapVisible(tester, find.text('Tylko dla X1C (ukryto 2)'));

      expect(
        find.text('Tylko dla X1C'),
        findsOneWidget,
        reason: 'nothing is hidden any more, so the count goes away',
      );
      await scrollTo(tester, find.text('Bambu ASA @BBL A1'));
      expect(find.text('Bambu ASA @BBL A1'), findsOneWidget);
    });

    testWidgets('an unknown printer model is said out loud, not filtered on', (
      tester,
    ) async {
      // Otherwise an unfiltered list looks exactly like a filter that does
      // nothing, and there is no way to tell which one it is.
      await openWith(tester, printerModel: null);

      expect(find.textContaining('Nieznany model drukarki'), findsOneWidget);
      await scrollTo(tester, find.text('Bambu ASA @BBL A1'));
      expect(find.text('Bambu ASA @BBL A1'), findsOneWidget);
    });
  });

  testWidgets('offers a cloud login when that is why the tier is missing', (
    tester,
  ) async {
    final repo = _FakeRepo()
      ..cloudError = const AuthException(AppErrorCode.unauthorized);
    await openSheet(tester, repo: repo);

    expect(find.textContaining('Zaloguj się do Bambu Cloud'), findsOneWidget);
    await scrollTo(tester, find.text('Generic PLA'));
    expect(
      find.text('Generic PLA'),
      findsOneWidget,
      reason: 'the other tiers still fill the picker',
    );
  });

  testWidgets('turning the filter off gives preselection another chance', (
    tester,
  ) async {
    // The slot is set to a preset the printer filter hides. Latching
    // preselection on the first list would leave it unmarked for good, so
    // "show everything" would list it as just another row.
    final repo = _FakeRepo()
      ..cloudPresets = const [
        AmsFilamentPreset(
          source: AmsPresetSource.cloud,
          id: 'GFSB99_09',
          name: 'Bambu ABS @BBL A1',
        ),
      ];
    await openSheet(
      tester,
      repo: repo,
      slot: const AmsSlotTarget(
        printerId: 1,
        amsId: 0,
        trayId: 2,
        label: 'AMS 1 · 3',
        printerModel: 'X1C',
        currentFilamentId: 'GFB99',
      ),
    );

    expect(
      find.text('Ustawiony teraz · Bambu Cloud'),
      findsNothing,
      reason: 'the filter hides it, so there is nothing to mark yet',
    );

    await tapVisible(tester, find.textContaining('Tylko dla X1C'));

    expect(find.text('Bambu ABS @BBL A1'), findsOneWidget);
    expect(find.text('Ustawiony teraz · Bambu Cloud'), findsOneWidget);
  });

  group('the K profile', () {
    const calibrated = KProfile(
      slotId: 4,
      name: 'PLA basic',
      kValue: '0.035000',
      filamentId: 'GFL99',
      settingId: 'PFUS7',
    );
    const forPetg = KProfile(
      slotId: 9,
      name: 'eSUN PETG dry',
      kValue: '0.048000',
      filamentId: 'GFG99',
    );

    testWidgets('says so when the printer holds no calibrations', (
      tester,
    ) async {
      // Hiding the field instead reads as the app not having the feature —
      // there is no way to tell that from a printer nobody has calibrated.
      await openSheet(tester);

      expect(find.text('Profil K'), findsOneWidget);
      expect(
        find.textContaining('nie ma zapisanych profili K'),
        findsOneWidget,
      );
    });

    testWidgets('a table that could not be read is not passed off as empty', (
      tester,
    ) async {
      // A disconnected printer answers 400 and a key without kprofiles:read
      // answers 403; neither is "you have no calibrations".
      final repo = _FakeRepo()..profilesError = Exception('nope');
      await openSheet(tester, repo: repo);

      expect(
        find.textContaining('Nie udało się odczytać profili K'),
        findsOneWidget,
      );
    });

    testWidgets('asks about the nozzle the slot feeds', (tester) async {
      final repo = await openSheet(tester);

      expect(repo.profilesNozzle, '0.6');
    });

    testWidgets('follows the preset that is picked', (tester) async {
      final repo = _FakeRepo()..profiles = const [calibrated, forPetg];
      await openSheet(tester, repo: repo);

      await tapVisible(tester, find.text('Generic PLA'));

      expect(
        find.text('PLA basic · K 0,035'),
        findsOneWidget,
        reason: 'the only calibration for this filament arms itself',
      );
    });

    testWidgets('the write carries the selected calibration', (tester) async {
      final repo = _FakeRepo()..profiles = const [calibrated];
      await openSheet(tester, repo: repo);

      await tapVisible(tester, find.text('Generic PLA'));
      await tapVisible(tester, find.text('Zapisz w drukarce'));

      final written = repo.written!;
      expect(written.caliIdx, 4);
      expect(written.kProfileFilamentId, 'GFL99');
      expect(written.kProfileSettingId, 'PFUS7');
      expect(written.kValue, 0.035);
    });

    testWidgets('an unreadable table does not wipe the slot calibration', (
      tester,
    ) async {
      // The write always carries a cali_idx, so -1 resets the printer to its
      // default K. Sending that because the table could not be read throws
      // away a calibration nobody was ever shown.
      final repo = _FakeRepo()..profilesError = Exception('nope');
      await openSheet(
        tester,
        repo: repo,
        slot: const AmsSlotTarget(
          printerId: 1,
          amsId: 0,
          trayId: 2,
          label: 'AMS 1 · 3',
          printerModel: 'X1C',
          nozzleDiameter: '0.6',
          currentCaliIdx: 6,
        ),
      );

      await tapVisible(tester, find.text('Generic PLA'));
      await tapVisible(tester, find.text('Zapisz w drukarce'));

      expect(repo.written!.caliIdx, 6);
    });

    testWidgets('choosing the default is honoured over what the slot had', (
      tester,
    ) async {
      // The rule above must not turn into "the user can never clear it".
      final repo = _FakeRepo()..profiles = const [calibrated];
      await openSheet(
        tester,
        repo: repo,
        slot: const AmsSlotTarget(
          printerId: 1,
          amsId: 0,
          trayId: 2,
          label: 'AMS 1 · 3',
          printerModel: 'X1C',
          nozzleDiameter: '0.6',
          currentCaliIdx: 6,
        ),
      );

      await tapVisible(tester, find.text('Generic PLA'));
      await tapVisible(tester, find.text('PLA basic · K 0,035'));
      await tapVisible(tester, find.text('Domyślny (K 0,020)').last);
      await tapVisible(tester, find.text('Zapisz w drukarce'));

      expect(repo.written!.caliIdx, -1);
    });

    testWidgets('the slot keeps the calibration it is printing with', (
      tester,
    ) async {
      // A profile bound to the slot need not agree with the preset's name;
      // dropping it would write the printer back to its default K in silence.
      final repo = _FakeRepo()..profiles = const [calibrated, forPetg];
      await openSheet(
        tester,
        repo: repo,
        slot: const AmsSlotTarget(
          printerId: 1,
          amsId: 0,
          trayId: 2,
          label: 'AMS 1 · 3',
          printerModel: 'X1C',
          nozzleDiameter: '0.6',
          currentCaliIdx: 9,
        ),
      );

      await tapVisible(tester, find.text('Generic PLA'));
      await tapVisible(tester, find.text('Zapisz w drukarce'));

      expect(repo.written!.caliIdx, 9);
    });

    testWidgets('the default clears it back to the printer default', (
      tester,
    ) async {
      final repo = _FakeRepo()..profiles = const [calibrated];
      await openSheet(tester, repo: repo);
      await tapVisible(tester, find.text('Generic PLA'));

      await tapVisible(tester, find.text('PLA basic · K 0,035'));
      await tapVisible(tester, find.text('Domyślny (K 0,020)').last);
      await tapVisible(tester, find.text('Zapisz w drukarce'));

      expect(repo.written!.caliIdx, -1);
      expect(repo.written!.kValue, 0);
    });

    testWidgets('changing the filament re-derives it', (tester) async {
      // A calibration belongs to one filament; carrying it across a change of
      // preset would print the wrong pressure advance under the right name.
      final repo = _FakeRepo()..profiles = const [calibrated, forPetg];
      await openSheet(tester, repo: repo);

      await tapVisible(tester, find.text('Generic PLA'));
      expect(find.text('PLA basic · K 0,035'), findsOneWidget);

      await tapVisible(tester, find.text('eSUN PETG'));

      expect(find.text('eSUN PETG dry · K 0,048'), findsOneWidget);
      expect(find.text('PLA basic · K 0,035'), findsNothing);
    });

    testWidgets('every calibration the printer holds stays reachable', (
      tester,
    ) async {
      // The match runs on names the user typed, so it will sometimes be
      // wrong — the printer's own table is what can actually be selected.
      final repo = _FakeRepo()..profiles = const [calibrated, forPetg];
      await openSheet(tester, repo: repo);
      await tapVisible(tester, find.text('Generic PLA'));

      await tapVisible(tester, find.text('PLA basic · K 0,035'));

      expect(find.text('Pozostałe profile'), findsOneWidget);
      expect(find.text('eSUN PETG dry · K 0,048'), findsOneWidget);
    });
  });

  group('the colour picker', () {
    const catalogue = [
      ColorEntry(
        id: 1,
        manufacturer: 'Bambu Lab',
        colorName: 'Bambu Green',
        hexColor: '#00AE42',
        material: 'PLA',
      ),
      ColorEntry(
        id: 2,
        manufacturer: 'Bambu Lab',
        colorName: 'Grey',
        hexColor: '#808080',
        material: 'PETG',
      ),
    ];

    testWidgets('offers the colours this filament is sold in', (tester) async {
      await openSheet(tester, colours: catalogue);
      await tapVisible(tester, find.text('Generic PLA'));

      // The field's own label floats above the tappable area, so the tap
      // goes to the row it decorates.
      await tapVisible(
        tester,
        find
            .ancestor(of: find.text('Kolor'), matching: find.byType(InkWell))
            .first,
      );

      expect(find.text('Kolory z katalogu'), findsOneWidget);
      expect(find.byTooltip('Bambu Green'), findsOneWidget);
      expect(
        find.byTooltip('Grey'),
        findsNothing,
        reason: 'PETG is a different filament',
      );
    });

    testWidgets('a catalogue colour is what gets written', (tester) async {
      final repo = await openSheet(tester, colours: catalogue);
      await tapVisible(tester, find.text('Generic PLA'));

      // The field's own label floats above the tappable area, so the tap
      // goes to the row it decorates.
      await tapVisible(
        tester,
        find
            .ancestor(of: find.text('Kolor'), matching: find.byType(InkWell))
            .first,
      );
      await tapVisible(tester, find.byTooltip('Bambu Green'));
      await tapVisible(tester, find.text('Wybierz'));
      await tapVisible(tester, find.text('Zapisz w drukarce'));

      expect(
        repo.written!.trayColour,
        '00AE42FF',
        reason: 'opaque, and no leading hash',
      );
    });

    testWidgets('the wheel alone still picks a colour', (tester) async {
      // No preset chosen, so no catalogue — the dialog must still work.
      final repo = await openSheet(tester, colours: catalogue);

      // The field's own label floats above the tappable area, so the tap
      // goes to the row it decorates.
      await tapVisible(
        tester,
        find
            .ancestor(of: find.text('Kolor'), matching: find.byType(InkWell))
            .first,
      );

      expect(find.text('Kolory z katalogu'), findsNothing);
      await tapVisible(tester, find.text('Anuluj'));
      expect(repo.written, isNull);
    });
  });
}
