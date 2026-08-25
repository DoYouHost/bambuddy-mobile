import 'package:bambuddy_mobile/core/api/server_version_service.dart';
import 'package:bambuddy_mobile/core/models/calibration_option.dart';
import 'package:bambuddy_mobile/core/models/plate_list.dart';
import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:bambuddy_mobile/core/settings/print_options.dart';
import 'package:bambuddy_mobile/core/settings/settings_repository.dart';
import 'package:bambuddy_mobile/data/queue_repository.dart';
import 'package:bambuddy_mobile/features/queue/queue_edit_screen.dart';
import 'package:bambuddy_mobile/features/queue/queue_providers.dart';
import 'package:bambuddy_mobile/features/slicer/slice_providers.dart';
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

const _printer = Printer(id: 1, name: 'X2D-3DP', model: 'X2D');

late SharedPreferences _prefs;

/// [triState] stands in for the server-version probe: `false` is what an older
/// server (or an unanswered probe) gives the form, `true` is bambuddy 1.2.5+.
/// [snippets] stands in for `AppSettings.gcode_snippets`: the printer models the
/// server has auto-print G-code for. Empty is the ordinary install, where the
/// injection checkbox has nothing to offer and stays off screen.
/// [plates] stands in for `GET /archives/{id}/plates`. The default is what
/// every server answers for a single-plate file — and what an older server
/// without the route answers for anything — so the plate section stays off
/// screen unless a test asks for it.
Widget _screen(
  QueueItem draft,
  QueueScheduleType schedule, {
  QueueEditMode mode = QueueEditMode.create,
  bool triState = false,
  Set<String> snippets = const {},
  PlateList plates = PlateList.none,
}) =>
    ProviderScope(
      overrides: [
        noServerProfileOverride,
        queueRepositoryProvider.overrideWithValue(_repo(triState: triState)),
        allPrintersProvider.overrideWith((ref) async => const [_printer]),
        sharedPreferencesProvider.overrideWithValue(_prefs),
        triStateCalibrationProvider.overrideWith((ref) async => triState),
        gcodeSnippetModelsProvider.overrideWith((ref) async => snippets),
        plateListProvider.overrideWith((ref, arg) async => plates),
        filamentRequirementsProvider.overrideWith((ref, arg) async => const []),
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
QueueItem _archiveDraft({bool manualStart = false, int? plateId}) =>
    QueueItem.draft(
      archiveId: 77,
      name: 'cube.3mf',
      printerId: 1,
      slicedForModel: 'X2D',
      plateId: plateId,
      manualStart: manualStart,
    );

/// Three plates, as a 3MF sliced for a plate farm answers.
PlateList _threePlates() => PlateList.fromJson({
      'plates': [
        for (var i = 1; i <= 3; i++)
          {'index': i, 'name': 'Plate $i', 'object_count': i, 'has_thumbnail': false},
      ],
      'is_multi_plate': true,
      'has_gcode': true,
    });

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

  // The gap this closes: the server starts a job on `plate_id or 1`, so a
  // reprint that drops the archive's plate prints plate 1 of a multi-plate file
  // instead of the plate the archive is a record of.
  testWidgets('reprint of a multi-plate archive sends the plate it ran on',
      (tester) async {
    await tester.pumpWidget(_screen(
      _archiveDraft(plateId: 3),
      QueueScheduleType.asap,
      plates: _threePlates(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Płyta 3 · Plate 3'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Drukuj'));
    await tester.pumpAndSettle();

    expect(_captured?['plate_id'], 3);
  });

  testWidgets('a single-plate file is offered no plate to choose',
      (tester) async {
    await tester.pumpWidget(_screen(_archiveDraft(), QueueScheduleType.asap));
    await tester.pumpAndSettle();

    expect(find.text('Płyta'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Drukuj'));
    await tester.pumpAndSettle();

    // Absent, not null: the server's own default has to stay in charge for
    // every install that never reported a plate.
    expect(_captured?.containsKey('plate_id'), isFalse);
  });

  testWidgets('picking another plate sends that one and drops the mapping',
      (tester) async {
    // The state the form is in after the user has been through the mapping
    // sheet: slots picked for the plate that was selected *then*.
    const mapped = QueueItem(
      id: 0,
      position: 0,
      status: 'pending',
      archiveId: 77,
      archiveName: 'cube.3mf',
      printerId: 1,
      slicedForModel: 'X2D',
      plateId: 1,
      amsMapping: [2, 0],
    );
    await tester.pumpWidget(_screen(
      mapped,
      QueueScheduleType.asap,
      plates: _threePlates(),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Płyta 1 · Plate 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Płyta 2 · Plate 2').last);
    await tester.pumpAndSettle();

    expect(find.text('Płyta 2 · Plate 2'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Drukuj'));
    await tester.pumpAndSettle();

    expect(_captured?['plate_id'], 2);
    // The mapping it was pre-filled with belongs to another plate's slots, so
    // it must not ride along — an absent mapping is the server auto-matching.
    expect(_captured?.containsKey('ams_mapping'), isFalse);
  });

  // Guards the test above: without a plate change the same form does send the
  // mapping, so its absence there is the reset and not just an empty form.
  testWidgets('an untouched plate keeps the mapping it was opened with',
      (tester) async {
    const mapped = QueueItem(
      id: 0,
      position: 0,
      status: 'pending',
      archiveId: 77,
      archiveName: 'cube.3mf',
      printerId: 1,
      slicedForModel: 'X2D',
      plateId: 1,
      amsMapping: [2, 0],
    );
    await tester.pumpWidget(_screen(
      mapped,
      QueueScheduleType.asap,
      plates: _threePlates(),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Drukuj'));
    await tester.pumpAndSettle();

    expect(_captured?['ams_mapping'], [2, 0]);
    expect(_captured?['plate_id'], 1);
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

  group('wstrzykiwanie G-code auto-druku', () {
    const label = 'Wstrzyknij G-code auto-druku';

    /// The flags sit at the bottom of a long form, so they must be scrolled to
    /// before a finder can see them at all — "Power off" is the last row that is
    /// always there, which makes it the anchor.
    Future<void> revealFlags(WidgetTester tester) async {
      await tester.dragUntilVisible(
        find.text('Wyłącz drukarkę po zakończeniu'),
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
    }

    Future<void> tapInjection(WidgetTester tester) async {
      await revealFlags(tester);
      await tester.ensureVisible(find.text(label));
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    /// The options blob a plate-swap user ends up with: injection remembered ON.
    Future<void> rememberInjection() => _prefs.setString(
          'print_options',
          const PrintOptions(
            bedLevelling: CalibrationOption.on,
            flowCali: CalibrationOption.on,
            vibrationCali: true,
            layerInspect: true,
            timelapse: false,
            nozzleOffsetCali: CalibrationOption.on,
            gcodeInjection: true,
          ).encode(),
        );

    testWidgets('serwer bez snippetów nie pokazuje opcji', (tester) async {
      await tester.pumpWidget(_screen(_archiveDraft(), QueueScheduleType.asap));
      await tester.pumpAndSettle();
      await revealFlags(tester);

      expect(find.text(label), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Drukuj'));
      await tester.pumpAndSettle();

      expect(_captured?.containsKey('gcode_injection'), isFalse,
          reason: 'flaga bez snippetów jest i tak bezczynna');
    });

    testWidgets('zaznaczona opcja jedzie z POST-em', (tester) async {
      await tester.pumpWidget(_screen(
        _archiveDraft(),
        QueueScheduleType.asap,
        snippets: {'X2D'},
      ));
      await tester.pumpAndSettle();

      await tapInjection(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Drukuj'));
      await tester.pumpAndSettle();

      expect(_captured?['gcode_injection'], true);
      expect(_stored().gcodeInjection, isTrue,
          reason: 'rig do wymiany płyty potrzebuje tego przy każdym wydruku');
    });

    testWidgets('zapamiętana opcja startuje zaznaczona', (tester) async {
      await rememberInjection();

      await tester.pumpWidget(_screen(
        _archiveDraft(),
        QueueScheduleType.asap,
        snippets: {'X2D'},
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Drukuj'));
      await tester.pumpAndSettle();

      expect(_captured?['gcode_injection'], true);
    });

    testWidgets('zapamiętana opcja nie jedzie na serwer bez snippetów',
        (tester) async {
      // Server without snippets: the flag must not ship at all, otherwise a
      // remembered ON keeps asking for an injection nobody configured.
      await rememberInjection();

      await tester.pumpWidget(_screen(_archiveDraft(), QueueScheduleType.asap));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Drukuj'));
      await tester.pumpAndSettle();

      expect(_captured?.containsKey('gcode_injection'), isFalse);
    });

    testWidgets('model docelowy bez snippetu mówi, że nic nie wstrzyknie',
        (tester) async {
      // Snippets exist, but for another model — the scheduler prints the file
      // untouched and says so only in its own log.
      await tester.pumpWidget(_screen(
        _archiveDraft(),
        QueueScheduleType.asap,
        snippets: {'A1 mini'},
      ));
      await tester.pumpAndSettle();
      await revealFlags(tester);

      expect(find.textContaining('nic nie zostanie wstrzyknięte'), findsNothing,
          reason: 'niezaznaczona opcja nie ma o czym ostrzegać');

      await tapInjection(tester);

      expect(find.textContaining('Brak G-code dla modelu X2D'),
          findsAtLeastNWidgets(1));
    });

    testWidgets('ostrzeżenie widać przy wyborze drukarki, bez scrollowania',
        (tester) async {
      // The reported hole: someone who only comes in to change the printer never
      // reaches the checkbox at the bottom, so the note has to be where the
      // choice is made.
      await rememberInjection();

      await tester.pumpWidget(_screen(
        _archiveDraft(),
        QueueScheduleType.asap,
        snippets: {'A1 mini'},
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('Brak G-code dla modelu X2D'), findsOneWidget,
          reason: 'sekcja Cel jest na pierwszym ekranie formularza');
    });

    testWidgets('edycja bez snippetów nie przepisuje zapisanej flagi',
        (tester) async {
      await tester.pumpWidget(_screen(
        QueueItem.fromJson({
          'id': 5,
          'position': 1,
          'status': 'pending',
          'archive_id': 77,
          'printer_id': 1,
          'gcode_injection': true,
        }),
        QueueScheduleType.queue,
        mode: QueueEditMode.edit,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Zapisz'));
      await tester.pumpAndSettle();

      expect(_captured?.containsKey('gcode_injection'), isFalse,
          reason: 'checkbox niewidoczny — nie wolno kasować wartości serwera');
    });
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
