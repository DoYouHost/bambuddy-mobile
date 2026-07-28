import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:bambuddy_mobile/core/settings/print_options.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/core/settings/settings_repository.dart';
import 'package:bambuddy_mobile/data/queue_repository.dart';
import 'package:bambuddy_mobile/features/queue/queue_edit_screen.dart';
import 'package:bambuddy_mobile/features/queue/queue_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

/// Body of the POST the form sent, captured before the mock adapter answers.
/// Asserting on it beats matching in the adapter: a mismatch then reads as
/// "these keys differ", not as an unexplained connection error.
Map<String, dynamic>? _captured;

QueueRepository _repo() {
  final dio = Dio(BaseOptions(baseUrl: 'http://s.local:8000'));
  dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
    _captured = options.data as Map<String, dynamic>?;
    handler.next(options);
  }));
  DioAdapter(dio: dio)
    ..onPost(
      '/api/v1/queue/',
      (server) => server.reply(200, null),
      data: Matchers.any,
    )
    ..onPatch(
      '/api/v1/queue/5',
      (server) => server.reply(200, null),
      data: Matchers.any,
    );
  return QueueRepository(dio);
}

/// Null profile: [QueueNotifier.refresh] short-circuits, so the only request
/// this screen makes is the create POST itself.
class _NullProfileNotifier extends ServerProfileNotifier {
  @override
  ServerProfile? build() => null;
}

const _printer = Printer(id: 1, name: 'X2D-3DP', model: 'X2D');

late SharedPreferences _prefs;

Widget _screen(
  QueueItem draft,
  QueueScheduleType schedule, {
  QueueEditMode mode = QueueEditMode.create,
}) =>
    ProviderScope(
      overrides: [
        serverProfileProvider.overrideWith(_NullProfileNotifier.new),
        queueRepositoryProvider.overrideWithValue(_repo()),
        allPrintersProvider.overrideWith((ref) async => const [_printer]),
        sharedPreferencesProvider.overrideWithValue(_prefs),
      ],
      child: plApp(QueueEditScreen(
        item: draft,
        mode: mode,
        initialSchedule: schedule,
      )),
    );

PrintOptions _stored() =>
    SettingsRepository(_prefs).loadPrintOptions();

/// Sliced for a dual-nozzle model, so the nozzle-offset toggle is on screen —
/// on a single-nozzle job the form hides it and omits it from the body.
QueueItem _archiveDraft({bool manualStart = false}) => QueueItem.draft(
      archiveId: 77,
      name: 'cube.3mf',
      printerId: 1,
      slicedForModel: 'X2D',
      manualStart: manualStart,
    );

void main() {
  setUp(() async {
    _captured = null;
    SharedPreferences.setMockInitialValues({});
    _prefs = await SharedPreferences.getInstance();
  });

  testWidgets('reprint: ASAP wysyła insert_at_top i nie wstrzymuje pozycji',
      (tester) async {
    await tester.pumpWidget(_screen(_archiveDraft(), QueueScheduleType.asap));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Drukuj'));
    await tester.pumpAndSettle();

    expect(_captured?['archive_id'], 77);
    expect(_captured?['printer_id'], 1);
    expect(_captured?['insert_at_top'], true);
    expect(_captured?['manual_start'], false);
    expect(_captured?.containsKey('scheduled_time'), isFalse);
  });

  testWidgets('dodaj do kolejki: pozycja powstaje wstrzymana, bez wyprzedzania',
      (tester) async {
    await tester.pumpWidget(
        _screen(_archiveDraft(manualStart: true), QueueScheduleType.queue));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Drukuj'));
    await tester.pumpAndSettle();

    // Wstrzymana od pierwszej chwili: scheduler jej nie zabierze, dopóki user
    // sam nie kliknie startu — to jest zamknięcie wyścigu z 06b.
    expect(_captured?['manual_start'], true);
    expect(_captured?.containsKey('insert_at_top'), isFalse);
  });

  testWidgets('pierwszy wydruk: włączone wszystko poza timelapse',
      (tester) async {
    await tester.pumpWidget(_screen(_archiveDraft(), QueueScheduleType.asap));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Drukuj'));
    await tester.pumpAndSettle();

    expect(_captured?['bed_levelling'], true);
    expect(_captured?['flow_cali'], true);
    expect(_captured?['vibration_cali'], true);
    expect(_captured?['layer_inspect'], true);
    expect(_captured?['timelapse'], false);
    // Widoczna tylko dla dwugłowicowych — szkic jest sliced_for_model X2D.
    expect(_captured?['nozzle_offset_cali'], true);
  });

  testWidgets('kolejny wydruk startuje z ostatnio użytych opcji',
      (tester) async {
    await _prefs.setString(
      'print_options',
      const PrintOptions(
        bedLevelling: false,
        flowCali: false,
        vibrationCali: true,
        layerInspect: false,
        timelapse: true,
        nozzleOffsetCali: true,
      ).encode(),
    );

    await tester.pumpWidget(_screen(_archiveDraft(), QueueScheduleType.asap));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Drukuj'));
    await tester.pumpAndSettle();

    expect(_captured?['bed_levelling'], false);
    expect(_captured?['flow_cali'], false);
    expect(_captured?['timelapse'], true);
  });

  testWidgets('udane utworzenie zapamiętuje przełączniki', (tester) async {
    await tester.pumpWidget(_screen(_archiveDraft(), QueueScheduleType.asap));
    await tester.pumpAndSettle();

    // Pierwszy przełącznik to poziomowanie stołu (domyślnie ON).
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Drukuj'));
    await tester.pumpAndSettle();

    expect(_stored().bedLevelling, false);
    expect(_stored().vibrationCali, true);
  });

  testWidgets('edycja pozycji nie przestawia zapamiętanych opcji',
      (tester) async {
    // Zmiana przy jednej pozycji dotyczy TEJ pozycji — inaczej jednorazowy
    // wyjątek szedłby za userem na wszystkie kolejne wydruki.
    final item = QueueItem.draft(archiveId: 77, name: 'cube.3mf', printerId: 1);
    await tester.pumpWidget(_screen(
      QueueItem.fromJson({
        'id': 5,
        'position': 1,
        'status': 'pending',
        'archive_id': item.archiveId,
        'printer_id': 1,
      }),
      QueueScheduleType.queue,
      mode: QueueEditMode.edit,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Zapisz'));
    await tester.pumpAndSettle();

    expect(_stored(), PrintOptions.initial);
  });

  testWidgets('opcje druku z formularza jadą razem z POST-em', (tester) async {
    await tester.pumpWidget(_screen(_archiveDraft(), QueueScheduleType.asap));
    await tester.pumpAndSettle();

    // Pierwszy przełącznik w sekcji opcji to poziomowanie stołu (domyślnie ON).
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Drukuj'));
    await tester.pumpAndSettle();

    expect(_captured?['bed_levelling'], false);
    expect(_captured?['vibration_cali'], true);
    expect(_captured?['preheat_override'], 'inherit');
  });

  testWidgets('wypełniona akcja mieści się w pasku przy dużej czcionce',
      (tester) async {
    // Pigułka w AppBarze ma 56 px wysokości do dyspozycji — przy powiększonej
    // czcionce urośnie, więc overflow byłby cichy do pierwszego zgłoszenia.
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(_screen(_archiveDraft(), QueueScheduleType.asap));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.widgetWithText(FilledButton, 'Drukuj'), findsOneWidget);
  });

  testWidgets('bez wybranej drukarki nic nie leci na serwer', (tester) async {
    await tester.pumpWidget(_screen(
      QueueItem.draft(archiveId: 77, name: 'cube.3mf'),
      QueueScheduleType.asap,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Drukuj'));
    await tester.pumpAndSettle();

    expect(_captured, isNull);
    expect(find.text('Wybierz drukarkę'), findsOneWidget);
  });
}
