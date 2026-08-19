import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/printable_object.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/data/skip_objects_repository.dart';
import 'package:bambuddy_mobile/features/dashboard/object_pick_mask.dart';
import 'package:bambuddy_mobile/features/dashboard/skip_objects_providers.dart';
import 'package:bambuddy_mobile/features/dashboard/skip_objects_screen.dart';
import 'package:bambuddy_mobile/features/dashboard/ws_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:typed_data';

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

/// Mask splitting the plate down the middle between the two fixture objects.
ObjectPickMask _halvesMask() {
  const size = 16;
  final rgba = Uint8List(size * size * 4);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final id = x < size ~/ 2 ? 421 : 512;
      final p = (y * size + x) * 4;
      rgba[p] = id & 0xFF;
      rgba[p + 1] = (id >> 8) & 0xFF;
      rgba[p + 3] = 255;
    }
  }
  return ObjectPickMask.fromRgba(rgba, size, size)!;
}

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
    ObjectPickMask? mask,
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
        objectPickMaskProvider(1).overrideWith((ref) async => mask),
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

  testWidgets('bez maski płyta rysuje jeden dotykalny znacznik na obiekt',
      (tester) async {
    await pumpScreen(tester);
    final handle = tester.ensureSemantics();

    // `_ObjectMarker` and `_ObjectTile` both call the same `_toggleSelected`
    // with no branching on the caller, so the list-row tests above already
    // cover the toggle logic itself; this just guards that the fallback plate
    // renders (and tags) one badge per object.
    expect(find.bySemanticsIdentifier('skip_objects.marker'), findsNWidgets(2));
    handle.dispose();
  });

  testWidgets('dotknięcie kształtu na płycie zaznacza obiekt spod palca',
      (tester) async {
    // Object 421 owns the plate's left half, 512 the right — so a tap resolved
    // through the mask has to name the half it landed in, which is the whole
    // point of drawing the real footprints instead of badges.
    await pumpScreen(tester, mask: _halvesMask());
    final handle = tester.ensureSemantics();

    // One overlay for the whole plate now, not one widget per object.
    expect(find.bySemanticsIdentifier('skip_objects.marker'), findsOneWidget);

    final plate = tester.getRect(find.byType(InteractiveViewer));
    await tester.tapAt(Offset(plate.center.dx + plate.width * 0.25, plate.center.dy));
    // The plate's double-tap-to-reset recogniser holds the tap until its own
    // timeout passes without a second one.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(find.text('Zaznaczono: 1'), findsOneWidget);
    await tester.tap(find.text('Pomiń'));
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    expect(
      find.descendant(of: dialog, matching: find.textContaining('Divider_right.stl')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.textContaining('Divider_left.stl')),
      findsNothing,
    );
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

  testWidgets(
      'obiekt zniknięty z odświeżenia w tle po zaznaczeniu nie leci w żądaniu mimo braku w dialogu',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 3600);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final repo = await pumpScreen(tester);

    await tapRow(tester, 'Divider_left.stl');
    await tapRow(tester, 'Divider_right.stl');
    expect(find.text('Zaznaczono: 2'), findsOneWidget);

    // The background poll (or a pull-to-refresh) reloads the objects from the
    // 3MF and 512 is no longer in it — while it's still in `_selected`. Drive
    // it through the screen's own pull-to-refresh rather than a raw
    // `ProviderContainer`, so the provider's periodic poll timer is torn down
    // the same well-trodden way every other test in this file already is.
    repo._objects = const PrintableObjects(
      objects: [PrintableObject(id: 421, name: 'Divider_left.stl', x: 104, y: 104)],
      total: 1,
      isPrinting: true,
      bboxAll: [88, 88, 168, 168],
    );
    await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pomiń'));
    await tester.pumpAndSettle();

    // The dialog only shows the survivor — singular phrasing, no trace of 512.
    expect(find.text('Pominąć ten obiekt?'), findsOneWidget);
    expect(find.textContaining('512'), findsNothing);

    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Pomiń'),
    ));
    await tester.pumpAndSettle();

    // The request must match exactly what the dialog showed — no phantom 512
    // riding along from the raw (now-stale) selection set.
    expect(repo.skipCalls, [
      [421],
    ]);
  });
}
