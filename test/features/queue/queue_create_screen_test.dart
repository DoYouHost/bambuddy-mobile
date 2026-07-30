import 'package:bambuddy_mobile/core/api/server_version_service.dart';
import 'package:bambuddy_mobile/core/models/calibration_option.dart';
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

/// [triState] is the server generation the whole screen talks to — the repository
/// reads it from the version endpoint exactly as it does in production, so the
/// form and the request body cannot disagree about what the server can store.
QueueRepository _repo({required bool triState}) {
  final dio = Dio(BaseOptions(baseUrl: 'http://s.local:8000'));
  dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
    // The version probe is a GET with no body; only the queue writes matter here.
    if (options.data != null) _captured = options.data as Map<String, dynamic>?;
    handler.next(options);
  }));
  DioAdapter(dio: dio)
    ..onGet(
      '/api/v1/updates/version',
      (server) => server.reply(200, {
        'version': triState ? '1.2.5.1' : '0.2.4.9',
        'repo': 'maziggy/bambuddy',
      }),
    )
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
  return QueueRepository(dio, ServerVersionService(dio));
}

/// Null profile: [QueueNotifier.refresh] short-circuits, so the only request
/// this screen makes is the create POST itself.
class _NullProfileNotifier extends ServerProfileNotifier {
  @override
  ServerProfile? build() => null;
}

const _printer = Printer(id: 1, name: 'X2D-3DP', model: 'X2D');

late SharedPreferences _prefs;

/// [triState] stands in for the server-version probe: `false` is what an older
/// server (or an unanswered probe) gives the form, `true` is bambuddy 1.2.5+.
Widget _screen(
  QueueItem draft,
  QueueScheduleType schedule, {
  QueueEditMode mode = QueueEditMode.create,
  bool triState = false,
}) =>
    ProviderScope(
      overrides: [
        serverProfileProvider.overrideWith(_NullProfileNotifier.new),
        queueRepositoryProvider.overrideWithValue(_repo(triState: triState)),
        allPrintersProvider.overrideWith((ref) async => const [_printer]),
        sharedPreferencesProvider.overrideWithValue(_prefs),
        triStateCalibrationProvider.overrideWith((ref) async => triState),
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
        bedLevelling: CalibrationOption.off,
        flowCali: CalibrationOption.off,
        vibrationCali: true,
        layerInspect: false,
        timelapse: true,
        nozzleOffsetCali: CalibrationOption.on,
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

    expect(_stored().bedLevelling, CalibrationOption.off);
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

  group('trójstanowe kalibracje', () {
    /// The item the edit tests start from: stored `auto` on bed levelling, which
    /// is the value a two-state form must not quietly rewrite.
    QueueItem storedAuto() => QueueItem.fromJson({
          'id': 5,
          'position': 1,
          'status': 'pending',
          'archive_id': 77,
          'printer_id': 1,
          'sliced_for_model': 'X2D',
          'bed_levelling': 'auto',
          'flow_cali': 'on',
          'nozzle_offset_cali': 'auto',
        });

    testWidgets('starszy serwer nie pokazuje pozycji Auto', (tester) async {
      await tester.pumpWidget(_screen(_archiveDraft(), QueueScheduleType.asap));
      await tester.pumpAndSettle();

      expect(find.text('Auto'), findsNothing,
          reason: 'serwer nie ma gdzie zapisać auto — nie obiecujemy go');
      expect(find.byType(Switch), isNot(findsNothing));
    });

    testWidgets('serwer 1.2.5 daje wybór Auto / Wł. / Wył.', (tester) async {
      await tester.pumpWidget(_screen(
        _archiveDraft(),
        QueueScheduleType.asap,
        triState: true,
      ));
      await tester.pumpAndSettle();

      // Trzy pola kalibracji na ekranie (poziomowanie, przepływ, offset dyszy).
      expect(find.text('Auto'), findsNWidgets(3));
    });

    testWidgets('wybrane Auto leci na serwer jako auto', (tester) async {
      await tester.pumpWidget(_screen(
        _archiveDraft(),
        QueueScheduleType.asap,
        triState: true,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Auto').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Drukuj'));
      await tester.pumpAndSettle();

      expect(_captured?['bed_levelling'], 'auto');
    });

    testWidgets('wybrane Auto zostaje zapamiętane na następny wydruk',
        (tester) async {
      // Trójstan pamiętamy tym samym mechanizmem co przełączniki: `on` na start
      // dla kogoś, kto nigdy nie konfigurował, potem to, co wybrał ostatnio.
      // Samą serializację pokrywa print_options_test; tu chodzi o to, że
      // formularz naprawdę ją zapisuje.
      await tester.pumpWidget(_screen(
        _archiveDraft(),
        QueueScheduleType.asap,
        triState: true,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Auto').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Drukuj'));
      await tester.pumpAndSettle();

      expect(_stored().bedLevelling, CalibrationOption.auto);
      expect(_stored().flowCali, CalibrationOption.on,
          reason: 'nietknięte zostaje tym, czym było');
    });

    testWidgets('następny wydruk startuje z zapamiętanego Auto', (tester) async {
      await _prefs.setString(
        'print_options',
        const PrintOptions(
          bedLevelling: CalibrationOption.auto,
          flowCali: CalibrationOption.on,
          vibrationCali: true,
          layerInspect: true,
          timelapse: false,
          nozzleOffsetCali: CalibrationOption.auto,
        ).encode(),
      );

      await tester.pumpWidget(_screen(
        _archiveDraft(),
        QueueScheduleType.asap,
        triState: true,
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Drukuj'));
      await tester.pumpAndSettle();

      // Bez żadnego tapnięcia w opcje: to, co zapamiętane, jedzie na serwer.
      expect(_captured?['bed_levelling'], 'auto');
      expect(_captured?['nozzle_offset_cali'], 'auto');
      expect(_captured?['flow_cali'], true,
          reason: 'on jedzie booleanem — rozumie go każda wersja serwera');
    });

    testWidgets('zapamiętane Auto na starym serwerze: ekran nie kłamie',
        (tester) async {
      // Jedyna droga, którą `auto` trafia do starego serwera: wybrane na
      // nowszym i zapamiętane, potem przełączenie apki na starszy. Formularz
      // rysuje wtedy przełącznik dwustanowy w pozycji ON i to ON musi się
      // zapisać. Wcześniej klucz wypadał z body, a domyślna serwera dla
      // `flow_cali` to `false` — user widział włączone, dostawał wyłączone.
      await _prefs.setString(
        'print_options',
        const PrintOptions(
          bedLevelling: CalibrationOption.auto,
          flowCali: CalibrationOption.auto,
          vibrationCali: true,
          layerInspect: true,
          timelapse: false,
          nozzleOffsetCali: CalibrationOption.auto,
        ).encode(),
      );

      await tester.pumpWidget(_screen(_archiveDraft(), QueueScheduleType.asap));
      await tester.pumpAndSettle();

      expect(find.text('Auto'), findsNothing,
          reason: 'stary serwer — trzech stanów nie ma');
      expect(
        tester.widgetList<Switch>(find.byType(Switch)).first.value,
        isTrue,
        reason: 'auto rysuje się jako włączone',
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Drukuj'));
      await tester.pumpAndSettle();

      expect(_captured?['bed_levelling'], true);
      expect(_captured?['flow_cali'], true,
          reason: 'to jest ten punkt: przełącznik ON, więc na serwer idzie ON');
      expect(_captured?['nozzle_offset_cali'], true);
    });

    testWidgets('nietknięte auto nie jest nadpisywane przy edycji',
        (tester) async {
      // Formularz dwustanowy rysuje auto jako ON. Odesłanie tego jako `true`
      // przepisałoby userowi auto na on — pole, którego nie tknął, ma nie
      // pojechać wcale.
      await tester.pumpWidget(_screen(
        storedAuto(),
        QueueScheduleType.queue,
        mode: QueueEditMode.edit,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Zapisz'));
      await tester.pumpAndSettle();

      expect(_captured?.containsKey('bed_levelling'), isFalse);
      expect(_captured?.containsKey('nozzle_offset_cali'), isFalse);
      expect(_captured?.containsKey('flow_cali'), isFalse,
          reason: 'on też nietknięte');
    });

    testWidgets('zmienione pole jedzie normalnie', (tester) async {
      await tester.pumpWidget(_screen(
        storedAuto(),
        QueueScheduleType.queue,
        mode: QueueEditMode.edit,
      ));
      await tester.pumpAndSettle();

      // Pierwszy przełącznik to poziomowanie stołu — auto rysuje się jako ON,
      // więc tapnięcie ustawia off.
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Zapisz'));
      await tester.pumpAndSettle();

      expect(_captured?['bed_levelling'], false);
      expect(_captured?.containsKey('flow_cali'), isFalse);
    });
  });
}
