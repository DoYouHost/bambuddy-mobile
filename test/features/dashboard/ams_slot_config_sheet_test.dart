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

/// Records what the sheet writes and can be told to withhold each source.
class _FakeRepo implements AmsSlotConfigRepository {
  final List<String> calls = [];
  Object? cloudError;
  Object? saveError;
  SlotConfiguration? written;
  String? cloudDetailId;

  @override
  Future<List<AmsFilamentPreset>> cloudFilaments() async {
    if (cloudError != null) throw cloudError!;
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

  @override
  Future<SlotPreset?> slotPreset(int printerId,
          {required int amsId, required int trayId}) async =>
      null;

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

  /// The sheet is a scrollable list inside a 75%-height panel, so the actions
  /// at its foot are below the fold on a phone-sized test window.
  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
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

    expect(names, containsAll(['eSUN PETG', 'Bambu PLA Basic', 'Generic PLA']));
    expect(names.indexOf('eSUN PETG'), lessThan(names.indexOf('Bambu PLA Basic')));
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

  testWidgets('a failed mapping save does not fail the write', (tester) async {
    // The filament is already set on the printer by then; reporting failure
    // would describe a change that did happen as one that did not.
    final repo = _FakeRepo()
      ..saveError = const AuthException(AppErrorCode.forbidden);
    await openSheet(tester, repo: repo);

    await tapVisible(tester, find.text('Generic PLA'));
    await tapVisible(tester, find.text('Zapisz w drukarce'));

    expect(repo.calls, ['configure:1:0:2', 'save:builtin_GFL99:Generic PLA']);
    expect(find.text('Konfigurowanie slotu…'), findsOneWidget);
  });

  testWidgets('the write waits for a preset to be picked', (tester) async {
    await openSheet(tester);

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

  testWidgets('offers a cloud login when that is why the tier is missing',
      (tester) async {
    final repo = _FakeRepo()
      ..cloudError = const AuthException(AppErrorCode.unauthorized);
    await openSheet(tester, repo: repo);

    expect(find.textContaining('Zaloguj się do Bambu Cloud'), findsOneWidget);
    expect(find.text('Generic PLA'), findsOneWidget,
        reason: 'the other tiers still fill the picker');
  });
}
