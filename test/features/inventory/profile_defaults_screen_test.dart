import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:bambuddy_mobile/data/profile_defaults_repository.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_providers.dart';
import 'package:bambuddy_mobile/features/inventory/profile_defaults_screen.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers.dart';

/// Settings → Profile defaults: the list, Apply and Delete. The repository is
/// the real one over a scripted server, so the requests counted are the ones a
/// tap sends.
class _FakeInventory extends InventoryNotifier {
  int refreshes = 0;

  @override
  Future<InventoryState> build() async => InventoryState(spools: []);

  @override
  Future<void> refresh({bool askBackend = false}) async => refreshes++;
}

ResponseBody _json(Object? body, [int status = 200]) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

Map<String, dynamic> _row(
  int id, {
  String color = '',
  String? preset = 'GFA00',
  int presets = 0,
  int k = 0,
}) => {
  'id': id,
  'brand': 'Bambu Lab',
  'material': 'PLA',
  'subtype': 'Basic',
  'color_name': color,
  'slicer_filament': preset,
  'slicer_filament_name': preset,
  'presets': [
    for (var i = 0; i < presets; i++)
      {'printer_model': 'M$i', 'nozzle_diameter': ''},
  ],
  'k_profiles': [
    for (var i = 0; i < k; i++) {'printer_id': i, 'k_value': 0.02},
  ],
  'updated_at': '2026-10-30T10:00:00',
};

const _list = '/api/v1/inventory/profile-defaults';

void main() {
  late ScriptedAdapter server;
  late _FakeInventory inventory;
  late List<Map<String, dynamic>> rows;

  Future<void> open(
    WidgetTester tester, {
    List<Map<String, dynamic>>? stored,
    Object? Function(RequestOptions o)? onWrite,
    double textScale = 1,
  }) async {
    rows = [
      ...(stored ?? [_row(1, presets: 2, k: 3), _row(2, color: 'Red')]),
    ];
    inventory = _FakeInventory();
    server = ScriptedAdapter((o) {
      if (o.method == 'GET' && o.path == _list) return _json(rows);
      if (onWrite != null) {
        final answered = onWrite(o);
        if (answered != null) return answered;
      }
      return _json({'detail': 'Not Found'}, 404);
    });
    final dio = testDio()..httpClientAdapter = server;
    await pumpPhone(
      tester,
      const ProfileDefaultsScreen(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      overrides: [
        noServerProfileOverride,
        inventoryProvider.overrideWith(() => inventory),
        profileDefaultsRepositoryProvider.overrideWithValue(
          ProfileDefaultsRepository(dio, () async => InventoryBackend.native),
        ),
      ],
    );
    await tester.pumpAndSettle();
  }

  List<String> writes() => [
    for (final r in server.requests)
      if (r.method != 'GET') '${r.method} ${r.path}',
  ];

  int listReads() =>
      server.requests.where((r) => r.method == 'GET' && r.path == _list).length;

  testWidgets('lists each default with its scope and what it holds', (
    tester,
  ) async {
    await open(tester);

    expect(find.text('Bambu Lab PLA Basic'), findsOneWidget);
    expect(
      find.text(
        [
          pl.inventoryProfileDefaultAllColors,
          pl.inventoryFieldSlicerPreset,
          pl.profileDefaultsModelPresets(2),
          pl.profileDefaultsKProfiles(3),
        ].join(' · '),
      ),
      findsOneWidget,
    );
    // A colour row names its colour in the title and is not "all colours".
    expect(find.text('Bambu Lab PLA Basic · Red'), findsOneWidget);
    expect(find.text(pl.profileDefaultsApply), findsNWidgets(2));
  });

  testWidgets('a default holding nothing but a preset says so, and one with '
      'nothing at all shows no summary line', (tester) async {
    await open(
      tester,
      stored: [
        _row(1, color: 'Blue'),
        _row(2, color: 'Green', preset: null),
      ],
    );

    expect(find.text(pl.inventoryFieldSlicerPreset), findsOneWidget);
    expect(find.text('Bambu Lab PLA Basic · Green'), findsOneWidget);
  });

  testWidgets('says so when nothing is saved', (tester) async {
    await open(tester, stored: const []);

    expect(find.text(pl.profileDefaultsEmpty), findsOneWidget);
    expect(find.text(pl.profileDefaultsApply), findsNothing);
  });

  group('apply', () {
    testWidgets('sends one POST for that row and says how many spools it '
        'filled', (tester) async {
      await open(
        tester,
        onWrite: (o) => o.method == 'POST' && o.path == '$_list/2/apply'
            ? _json({'updated': 3})
            : null,
      );

      await tester.tap(find.text(pl.profileDefaultsApply).last);
      await tester.pumpAndSettle();

      expect(writes(), ['POST $_list/2/apply']);
      expect(find.text(pl.profileDefaultsApplied(3)), findsOneWidget);
      expect(inventory.refreshes, 1);
    });

    testWidgets('zero is a sentence of its own and leaves the shelf alone', (
      tester,
    ) async {
      await open(
        tester,
        onWrite: (o) => o.method == 'POST' ? _json({'updated': 0}) : null,
      );

      await tester.tap(find.text(pl.profileDefaultsApply).first);
      await tester.pumpAndSettle();

      expect(find.text(pl.profileDefaultsApplied(0)), findsOneWidget);
      expect(inventory.refreshes, 0);
    });

    testWidgets('a second tap while the first is in flight sends nothing', (
      tester,
    ) async {
      final gate = Completer<void>();
      await open(
        tester,
        onWrite: (o) => o.method == 'POST'
            // The body arrives only when the test says so.
            ? ResponseBody(
                Stream.fromFuture(
                  gate.future.then(
                    (_) => Uint8List.fromList(utf8.encode('{"updated":1}')),
                  ),
                ),
                200,
                headers: {
                  Headers.contentTypeHeader: [Headers.jsonContentType],
                },
              )
            : null,
      );

      await tester.tap(find.text(pl.profileDefaultsApply).first);
      await tester.pump();
      expect(
        tester
            .widgetList<TextButton>(find.byType(TextButton))
            .every((b) => b.onPressed == null),
        isTrue,
      );
      await tester.tap(find.text(pl.profileDefaultsApply).last);
      await tester.pump();

      gate.complete();
      await tester.pumpAndSettle();

      expect(writes(), ['POST $_list/1/apply']);
      expect(
        tester
            .widgetList<TextButton>(find.byType(TextButton))
            .every((b) => b.onPressed != null),
        isTrue,
      );
    });

    testWidgets('a refusal is said in the server\'s words and nothing is '
        'reloaded', (tester) async {
      await open(
        tester,
        onWrite: (o) => o.method == 'POST'
            ? _json({'detail': 'Missing required permissions'}, 403)
            : null,
      );

      await tester.tap(find.text(pl.profileDefaultsApply).first);
      await tester.pumpAndSettle();

      expect(find.text(pl.profileDefaultsApplied(0)), findsNothing);
      expect(
        find.textContaining('Missing required permissions'),
        findsOneWidget,
      );
      expect(inventory.refreshes, 0);
    });
  });

  group('delete', () {
    testWidgets('asks first, and Cancel sends nothing', (tester) async {
      await open(tester);

      await tester.tap(find.text(pl.inventoryDelete).first);
      await tester.pumpAndSettle();
      expect(find.text(pl.profileDefaultsDeleteTitle), findsOneWidget);
      expect(
        find.text(pl.profileDefaultsDeleteBody('Bambu Lab PLA Basic')),
        findsOneWidget,
      );
      await tester.tap(find.text(pl.cancel));
      await tester.pumpAndSettle();

      expect(writes(), isEmpty);
      expect(find.text('Bambu Lab PLA Basic'), findsOneWidget);
    });

    testWidgets('confirming deletes that row and reads the list again', (
      tester,
    ) async {
      await open(
        tester,
        onWrite: (o) {
          if (o.method == 'DELETE' && o.path == '$_list/2') {
            rows.removeWhere((r) => r['id'] == 2);
            return _json({'status': 'deleted'});
          }
          return null;
        },
      );
      expect(listReads(), 1);

      await tester.tap(find.text(pl.inventoryDelete).last);
      await tester.pumpAndSettle();
      expect(
        find.text(pl.profileDefaultsDeleteBody('Bambu Lab PLA Basic · Red')),
        findsOneWidget,
      );
      await tester.tap(find.text(pl.inventoryDelete).last);
      await tester.pumpAndSettle();

      expect(writes(), ['DELETE $_list/2']);
      expect(listReads(), 2);
      expect(find.text('Bambu Lab PLA Basic · Red'), findsNothing);
      expect(find.text('Bambu Lab PLA Basic'), findsOneWidget);
    });

    testWidgets('a refused delete leaves the row and says why', (tester) async {
      await open(
        tester,
        onWrite: (o) => o.method == 'DELETE'
            ? _json({'detail': 'This default holds K profiles'}, 403)
            : null,
      );

      await tester.tap(find.text(pl.inventoryDelete).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(pl.inventoryDelete).last);
      await tester.pumpAndSettle();

      expect(find.text('Bambu Lab PLA Basic'), findsOneWidget);
      expect(
        find.textContaining('This default holds K profiles'),
        findsOneWidget,
      );
    });
  });

  testWidgets('a failed read offers a retry', (tester) async {
    usePhoneWindow(tester);
    server = ScriptedAdapter((_) => _json({'detail': 'boom'}, 500));
    final dio = testDio()..httpClientAdapter = server;
    await pumpPhone(
      tester,
      const ProfileDefaultsScreen(),
      overrides: [
        noServerProfileOverride,
        profileDefaultsRepositoryProvider.overrideWithValue(
          ProfileDefaultsRepository(dio, () async => InventoryBackend.native),
        ),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.text(pl.retry), findsOneWidget);
  });

  for (final scale in const [1.0, 1.5, 2.0]) {
    testWidgets('cards and buttons fit at text scale $scale', (tester) async {
      usePhoneWindow(tester, dp: 1400);
      await open(tester, textScale: scale);

      expect(tester.takeException(), isNull);
      for (final button in tester.widgetList<TextButton>(
        find.byType(TextButton),
      )) {
        final size = tester.getSize(find.byWidget(button));
        expect(size.height, greaterThanOrEqualTo(48));
      }
    });
  }
}
