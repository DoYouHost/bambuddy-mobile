import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/printable_object.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/data/skip_objects_repository.dart';
import 'package:bambuddy_mobile/features/dashboard/skip_objects_screen.dart';
import 'package:bambuddy_mobile/features/dashboard/ws_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

/// Status with an externally-set layer — drives the layer>1 gate on the screen.
class _FixedLayerStatuses extends PrinterStatusesNotifier {
  _FixedLayerStatuses(this.layerNum);

  final int layerNum;

  @override
  Map<int, PrinterStatus> build() => {1: PrinterStatus(id: 1, layerNum: layerNum)};
}

/// No-network repository: hands back a fixed object list and records every
/// skip (batch) call, so a test can assert ONE request carries every selected
/// id, not one request per object.
class _StubRepo extends SkipObjectsRepository {
  _StubRepo(this._objects) : super(Dio());

  PrintableObjects _objects;
  final List<List<int>> skipCalls = [];
  Object? error;

  @override
  Future<PrintableObjects> fetchObjects(int printerId, {bool reload = false}) async =>
      _objects;

  @override
  Future<void> skip(int printerId, List<int> objectIds) async {
    skipCalls.add(objectIds);
    if (error != null) throw error!;
    _objects = PrintableObjects(
      objects: [
        for (final o in _objects.objects)
          if (objectIds.contains(o.id))
            PrintableObject(id: o.id, name: o.name, x: o.x, y: o.y, skipped: true)
          else
            o,
      ],
      total: _objects.total,
      skippedCount: _objects.skippedCount + objectIds.length,
      isPrinting: _objects.isPrinting,
      bboxAll: _objects.bboxAll,
    );
  }
}

const _twoObjects = PrintableObjects(
  objects: [
    PrintableObject(id: 421, name: 'Divider_left.stl', x: 104, y: 104),
    PrintableObject(id: 512, name: 'Divider_right.stl', x: 152, y: 104),
  ],
  total: 2,
  isPrinting: true,
  bboxAll: [88, 88, 168, 168],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Future<_StubRepo> pumpScreen(
    WidgetTester tester, {
    PrintableObjects objects = _twoObjects,
    int layerNum = 2,
  }) async {
    // The test window defaults to 800×600 (wider than tall) — the square plate
    // preview (AspectRatio 1) would then claim the whole viewport height, and
    // the sliver never builds the list rows underneath it. A phone-shaped
    // window fixes that the same way other screen tests in this repo do.
    tester.view.physicalSize = const Size(1080, 3600);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final repo = _StubRepo(objects);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        skipObjectsRepositoryProvider.overrideWithValue(repo),
        printerStatusesProvider.overrideWith(() => _FixedLayerStatuses(layerNum)),
      ],
      child: plApp(const SkipObjectsScreen(printerId: 1, printerName: 'X1 Carbon')),
    ));
    await tester.pumpAndSettle();
    return repo;
  }

  Future<void> tapRow(WidgetTester tester, String name) async {
    await tester.ensureVisible(find.text(name));
    await tester.tap(find.text(name));
    await tester.pump();
  }

  testWidgets(
      'zaznaczenie dwóch obiektów z listy i potwierdzenie wysyła jedno żądanie z obiema ID',
      (tester) async {
    final repo = await pumpScreen(tester);

    // Nothing selected yet, so no bottom confirmation bar.
    expect(find.text('Pomiń'), findsNothing);

    await tapRow(tester, 'Divider_left.stl');
    await tapRow(tester, 'Divider_right.stl');

    // Bottom bar: selected-count label + "Pomiń" button.
    expect(find.text('Zaznaczono: 2'), findsOneWidget);
    expect(find.text('Pomiń'), findsOneWidget);

    await tester.tap(find.text('Pomiń'));
    await tester.pumpAndSettle();

    // The dialog asks about both names at once; 2-4 is the "obiekty" plural.
    expect(find.text('Pominąć 2 obiekty?'), findsOneWidget);
    expect(
      find.textContaining('Divider_left.stl, Divider_right.stl'),
      findsOneWidget,
    );

    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Pomiń'),
    ));
    await tester.pumpAndSettle();

    // One request carrying both ids — not two separate calls.
    expect(repo.skipCalls, [
      [421, 512],
    ]);
    expect(find.text('Pominięto 2 obiekty'), findsOneWidget);
    // Selection and the bottom bar clear after success.
    expect(find.text('Pomiń'), findsNothing);
  });

  testWidgets('ponowne dotknięcie tego samego wiersza odznacza obiekt',
      (tester) async {
    final repo = await pumpScreen(tester);

    await tapRow(tester, 'Divider_left.stl');
    expect(find.text('Zaznaczono: 1'), findsOneWidget);

    await tapRow(tester, 'Divider_left.stl');

    expect(find.text('Pomiń'), findsNothing);
    expect(repo.skipCalls, isEmpty);
  });

  testWidgets('płyta rysuje jeden dotykalny kształt na obiekt', (tester) async {
    await pumpScreen(tester);
    final handle = tester.ensureSemantics();

    // `_ObjectMarker` and `_ObjectTile` both call the same `_toggleSelected`
    // with no branching on the caller, so the list-row tests above already
    // cover the toggle logic itself; this just guards that the plate actually
    // renders (and tags) one shape per object.
    expect(find.bySemanticsIdentifier('skip_objects.marker'), findsNWidgets(2));
    handle.dispose();
  });

  testWidgets('warstwa 1 blokuje zaznaczanie', (tester) async {
    await pumpScreen(tester, layerNum: 1);

    await tapRow(tester, 'Divider_left.stl');

    expect(find.text('Pomiń'), findsNothing);
  });

  testWidgets(
      '403 na batchu ustawia sticky forbidden i blokuje kolejne potwierdzenie',
      (tester) async {
    final repo = await pumpScreen(tester);
    repo.error = const AuthException(AppErrorCode.forbidden);

    await tapRow(tester, 'Divider_left.stl');
    await tester.tap(find.text('Pomiń'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Pomiń'),
    ));
    await tester.pumpAndSettle();

    expect(repo.skipCalls, hasLength(1));
    // Selection survives the failure, but the bar is now locked out.
    final button =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Pomiń'));
    expect(button.onPressed, isNull);
  });
}
