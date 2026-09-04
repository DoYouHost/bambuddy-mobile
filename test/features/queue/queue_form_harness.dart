import 'package:bambuddy_mobile/core/api/server_version_service.dart';
import 'package:bambuddy_mobile/core/models/filament_requirement.dart';
import 'package:bambuddy_mobile/core/models/plate_list.dart';
import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:bambuddy_mobile/core/settings/print_options.dart';
import 'package:bambuddy_mobile/core/settings/settings_repository.dart';
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

/// Shared rig for the print-form widget tests — [QueueEditScreen] in both modes.
///
/// One screen serves create and edit, and every test of it needs the same four
/// things: a repository whose writes can be read back, the overrides that keep
/// the form off the network, mock preferences for the remembered print options,
/// and a draft to open it with. Two files spelled all of that out separately
/// until the nozzle-rack picker needed one more override, which is the point at
/// which two copies start answering differently.

/// The labels the form is rendered with — `plApp` forces Polish, so a finder
/// asking for one reads it from here rather than repeating the translation.
final formL10n = lookupAppLocalizations(const Locale('pl'));

/// Body of the last write the form sent, captured before the mock answers.
///
/// Asserting on it beats matching in the adapter: a mismatch then reads as
/// "these keys differ", not as an unexplained connection error.
Map<String, dynamic>? capturedBody;

/// Preferences the form reads its remembered print options from, and writes
/// them back to. Valid from [setUpQueueForm] onwards.
late SharedPreferences queueFormPrefs;

/// Call from `setUp`: forgets the previous body and hands out empty
/// preferences, so a remembered option cannot leak from one test into the next.
Future<void> setUpQueueForm() async {
  capturedBody = null;
  SharedPreferences.setMockInitialValues({});
  queueFormPrefs = await SharedPreferences.getInstance();
}

/// What the form has saved for the next job.
PrintOptions storedPrintOptions() =>
    SettingsRepository(queueFormPrefs).loadPrintOptions();

/// The default target: a dual-nozzle model, so the nozzle-offset option is on
/// screen. A single-nozzle job hides it, which would silently narrow half the
/// assertions here.
const printerX2D = Printer(id: 1, name: 'X2D-3DP', model: 'X2D');

/// A nozzle-rack machine, for the rack picker. Same id as [printerX2D] so a
/// draft naming printer 1 works with either.
const printerH2C = Printer(id: 1, name: 'H2C-1', model: 'H2C');

/// [triState] is the server generation the whole screen talks to — the
/// repository reads it from the version endpoint exactly as it does in
/// production, so the form and the request body cannot disagree about what the
/// server can store.
QueueRepository queueFormRepo({required bool triState}) {
  final dio = Dio(BaseOptions(baseUrl: 'http://s.local:8000'));
  dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
    // The version probe is a GET with no body; only the queue writes matter.
    if (options.data != null) {
      capturedBody = options.data as Map<String, dynamic>?;
    }
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

/// The print form, wired to answers instead of a server.
///
/// Every knob stands in for one thing the screen asks the network for, and each
/// default is what the ordinary install answers — so a test names only what it
/// is actually about:
///
/// - [triState]: `false` is an older server (or a probe that has not answered),
///   `true` is bambuddy 1.2.5+, which can store `auto` on the calibrations.
/// - [snippets]: `AppSettings.gcode_snippets`, the printer models the server has
///   auto-print G-code for. Empty is the ordinary install, where the injection
///   checkbox has nothing to offer and stays off screen.
/// - [plates]: `GET /archives/{id}/plates`. The default is what every server
///   answers for a single-plate file — and what a server without the route
///   answers for anything — so the plate section stays hidden unless asked for.
/// - [requirements] and [nozzleRack]: the filament groups a plate declares and
///   the rack a printer reports. Both empty is every job on every printer
///   without a rack, and everything at all on a server that predates them.
Widget queueFormScreen(
  QueueItem item, {
  QueueScheduleType schedule = QueueScheduleType.asap,
  QueueEditMode mode = QueueEditMode.create,
  bool triState = false,
  Set<String> snippets = const {},
  PlateList plates = PlateList.none,
  List<Printer> printers = const [printerX2D],
  List<FilamentRequirement> requirements = const [],
  List<NozzleRackSlot>? nozzleRack,
}) =>
    ProviderScope(
      overrides: [
        noServerProfileOverride,
        queueRepositoryProvider
            .overrideWithValue(queueFormRepo(triState: triState)),
        allPrintersProvider.overrideWith((ref) async => printers),
        sharedPreferencesProvider.overrideWithValue(queueFormPrefs),
        triStateCalibrationProvider.overrideWith((ref) async => triState),
        gcodeSnippetModelsProvider.overrideWith((ref) async => snippets),
        plateListProvider.overrideWith((ref, arg) async => plates),
        filamentRequirementsProvider
            .overrideWith((ref, arg) async => requirements),
        printerStatusOnceProvider.overrideWith(
          (ref, id) async => PrinterStatus(id: id, nozzleRack: nozzleRack),
        ),
      ],
      child: plApp(QueueEditScreen(
        item: item,
        mode: mode,
        initialSchedule: schedule,
      )),
    );

/// A reprint draft of an archive, sliced for [model].
QueueItem archiveDraft({
  bool manualStart = false,
  int? plateId,
  int? printerId = 1,
  String model = 'X2D',
}) =>
    QueueItem.draft(
      archiveId: 77,
      name: 'cube.3mf',
      printerId: printerId,
      slicedForModel: model,
      plateId: plateId,
      manualStart: manualStart,
    );

/// Presses the one action of the form, whichever mode it is in.
Future<void> submitQueueForm(WidgetTester tester, {bool edit = false}) async {
  await tester.tap(find.widgetWithText(FilledButton,
      edit ? formL10n.queueEditSave : formL10n.queueCreateSubmit));
  await tester.pumpAndSettle();
}
