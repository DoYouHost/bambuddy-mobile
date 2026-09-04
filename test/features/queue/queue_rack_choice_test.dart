import 'package:bambuddy_mobile/core/api/server_version_service.dart';
import 'package:bambuddy_mobile/core/models/filament_requirement.dart';
import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:bambuddy_mobile/core/printers/nozzle_rack.dart';
import 'package:bambuddy_mobile/data/queue_repository.dart';
import 'package:bambuddy_mobile/features/queue/queue_edit_screen.dart';
import 'package:bambuddy_mobile/features/queue/queue_providers.dart';
import 'package:bambuddy_mobile/features/slicer/slice_providers.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

/// The H2C rack pick as the print form offers it (server #1784).
///
/// The compatibility gate under test is that nothing here is version-checked:
/// the section appears only when the plate declares filament groups AND the
/// printer reports a rack, and an older server does neither — so the same build
/// talks to both generations and only sends the field where it means something.

/// Body of the write the form sent, captured before the mock answers.
Map<String, dynamic>? _captured;

QueueRepository _repo() {
  final dio = Dio(BaseOptions(baseUrl: 'http://s.local:8000'));
  dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
    if (options.data != null) _captured = options.data as Map<String, dynamic>?;
    handler.next(options);
  }));
  DioAdapter(dio: dio)
    ..onGet(
      '/api/v1/updates/version',
      (server) => server.reply(200, {
        'version': '1.2.6',
        'repo': 'maziggy/bambuddy',
      }),
    )
    ..onPost('/api/v1/queue/', (server) => server.reply(200, null),
        data: Matchers.any)
    ..onPatch('/api/v1/queue/5', (server) => server.reply(200, null),
        data: Matchers.any);
  return QueueRepository(dio, ServerVersionService(dio));
}

const _printer = Printer(id: 1, name: 'H2C-1', model: 'H2C');

late SharedPreferences _prefs;
final _l10n = lookupAppLocalizations(const Locale('pl'));

/// Two 0.4 nozzles the plate can print from, one 0.6 it cannot, and three empty
/// docks — the rack of a machine in ordinary use.
List<NozzleRackSlot> _rack() => const [
      NozzleRackSlot(id: 16, nozzleDiameter: '0.4', nozzleType: 'HS01'),
      NozzleRackSlot(id: 17, nozzleDiameter: '0.6', nozzleType: 'HS01'),
      NozzleRackSlot(id: 18, nozzleDiameter: '0.4', nozzleType: 'HS01'),
      NozzleRackSlot(id: 19, nozzleDiameter: '', nozzleType: ''),
      NozzleRackSlot(id: 20, nozzleDiameter: '', nozzleType: ''),
      NozzleRackSlot(id: 21, nozzleDiameter: '', nozzleType: ''),
    ];

/// One filament, one rack-bound group wanting a 0.4 standard nozzle.
List<FilamentRequirement> _oneRackGroup() => FilamentRequirement.parseList({
      'filaments': [
        {
          'slot_id': 1,
          'type': 'PLA',
          'color': '#FF0000',
          'group_id': 1,
          'group': {
            'on_rack': true,
            'nozzle_diameter': '0.40',
            'volume_type': 'Standard',
            'filament_color': '#FF0000',
          },
        },
      ],
    });

Widget _screen(
  QueueItem item, {
  QueueEditMode mode = QueueEditMode.create,
  List<NozzleRackSlot>? rack,
  List<FilamentRequirement> requirements = const [],
}) =>
    ProviderScope(
      overrides: [
        noServerProfileOverride,
        queueRepositoryProvider.overrideWithValue(_repo()),
        allPrintersProvider.overrideWith((ref) async => const [_printer]),
        sharedPreferencesProvider.overrideWithValue(_prefs),
        triStateCalibrationProvider.overrideWith((ref) async => true),
        gcodeSnippetModelsProvider.overrideWith((ref) async => const <String>{}),
        filamentRequirementsProvider
            .overrideWith((ref, arg) async => requirements),
        printerStatusOnceProvider.overrideWith(
          (ref, id) async => PrinterStatus(id: id, nozzleRack: rack),
        ),
      ],
      child: plApp(QueueEditScreen(item: item, mode: mode)),
    );

QueueItem _draft() => QueueItem.draft(
      archiveId: 77,
      name: 'cube.3mf',
      printerId: 1,
      slicedForModel: 'H2C',
    );

/// Opens the group's dropdown and returns the labels it offered, in order.
Future<List<String>> _openPicker(WidgetTester tester) async {
  await tester.tap(find.textContaining(_l10n.nozzleFlowStandard).first);
  await tester.pumpAndSettle();
  return [
    for (final item in tester.widgetList<MenuItemButton>(
        find.byType(MenuItemButton)))
      ((item.child as Text?)?.data) ?? '',
  ];
}

void main() {
  setUp(() async {
    _captured = null;
    SharedPreferences.setMockInitialValues({});
    _prefs = await SharedPreferences.getInstance();
  });

  testWidgets('a plate with no rack groups is offered no pick', (tester) async {
    // What every non-H2C job looks like, and what every plate looks like on a
    // server that does not annotate the group table.
    await tester.pumpWidget(_screen(_draft(), rack: _rack()));
    await tester.pumpAndSettle();

    expect(find.text(_l10n.queueEditNozzleRack), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Drukuj'));
    await tester.pumpAndSettle();

    expect(_captured?.containsKey('nozzle_rack_choice'), isFalse);
  });

  testWidgets('a printer that reports no rack is offered no pick',
      (tester) async {
    await tester.pumpWidget(
        _screen(_draft(), requirements: _oneRackGroup()));
    await tester.pumpAndSettle();

    expect(find.text(_l10n.queueEditNozzleRack), findsNothing);
  });

  testWidgets('picking a position sends it keyed by the filament group',
      (tester) async {
    await tester.pumpWidget(
        _screen(_draft(), rack: _rack(), requirements: _oneRackGroup()));
    await tester.pumpAndSettle();

    expect(find.text(_l10n.queueEditNozzleRack), findsOneWidget);

    await _openPicker(tester);
    await tester.tap(find.text(
        _l10n.queueEditRackPosition(3, '0.4 ${_l10n.nozzleFlowStandard}')));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Drukuj'));
    await tester.pumpAndSettle();

    // Group ids are object keys on the wire, so they arrive stringified — the
    // server parses them back to ints.
    expect(_captured?['nozzle_rack_choice'], {'1': 3});
  });

  testWidgets('a position the nozzle does not fit cannot be picked',
      (tester) async {
    await tester.pumpWidget(
        _screen(_draft(), rack: _rack(), requirements: _oneRackGroup()));
    await tester.pumpAndSettle();

    await _openPicker(tester);
    final entries = tester
        .widgetList<MenuItemButton>(find.byType(MenuItemButton))
        .toList();
    final labels = [
      for (final entry in entries) ((entry.child as Text?)?.data) ?? '',
    ];
    final enabled = {
      for (var i = 0; i < entries.length; i++)
        if (entries[i].onPressed != null) labels[i],
    };

    // The 0.6 in position 2 and the three empty docks are shown — a choice the
    // form cannot honour says why it is unavailable — but none can be taken.
    expect(labels, hasLength(rackPositions.length + 1));
    expect(enabled, {
      _l10n.queueEditRackAuto,
      _l10n.queueEditRackPosition(1, '0.4 ${_l10n.nozzleFlowStandard}'),
      _l10n.queueEditRackPosition(3, '0.4 ${_l10n.nozzleFlowStandard}'),
    });
  });

  testWidgets('editing starts from the stored pick and can clear it',
      (tester) async {
    final item = QueueItem.fromJson({
      'id': 5,
      'position': 1,
      'status': 'pending',
      'printer_id': 1,
      'archive_id': 77,
      'archive_name': 'cube.3mf',
      'nozzle_rack_choice': {'1': 3},
    });

    await tester.pumpWidget(_screen(
      item,
      mode: QueueEditMode.edit,
      rack: _rack(),
      requirements: _oneRackGroup(),
    ));
    await tester.pumpAndSettle();

    expect(
      find.text(
          _l10n.queueEditRackPosition(3, '0.4 ${_l10n.nozzleFlowStandard}')),
      findsOneWidget,
    );

    await _openPicker(tester);
    await tester.tap(find.text(_l10n.queueEditRackAuto).last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Zapisz'));
    await tester.pumpAndSettle();

    // Explicitly null, not absent: the item still carries a pick, and only a
    // null clears it.
    expect(_captured?.containsKey('nozzle_rack_choice'), isTrue);
    expect(_captured?['nozzle_rack_choice'], isNull);
  });
}
