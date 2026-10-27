import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:app_test_kit/app_test_kit.dart';
import 'package:app_report_ui/app_report_ui.dart';
import 'package:bambuddy_mobile/core/models/announcement.dart';
import 'package:bambuddy_mobile/features/announcements/announcements_providers.dart';
import 'package:bambuddy_mobile/core/diagnostics/report_config.dart';
import 'dart:async';
import 'dart:io';

import 'package:bambuddy_mobile/core/api/media_auth.dart';
import 'package:bambuddy_mobile/core/auth/credentials_store.dart';
import 'package:bambuddy_mobile/core/models/archive.dart';
import 'package:bambuddy_mobile/core/models/current_user.dart';
import 'package:bambuddy_mobile/core/notifications/background_monitor.dart';
import 'package:bambuddy_mobile/core/notifications/background_sync.dart';
import 'package:bambuddy_mobile/core/notifications/notification_prefs.dart';
import 'package:bambuddy_mobile/core/notifications/notification_service.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/core/watch/watch_config_sync.dart';
import 'package:bambuddy_mobile/data/printer_commands_repository.dart';
import 'package:bambuddy_mobile/features/archive/archive_providers.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/features/admin/users_providers.dart';
import 'package:bambuddy_mobile/features/dashboard/firmware_providers.dart';
import 'package:bambuddy_mobile/features/dashboard/providers.dart';
import 'package:bambuddy_mobile/features/dashboard/smart_plugs_providers.dart';
import 'package:bambuddy_mobile/features/dashboard/ws_providers.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_providers.dart';
import 'package:bambuddy_mobile/features/dashboard/widgets/ams_history_sheet.dart';
import 'package:bambuddy_mobile/features/dashboard/widgets/heater_history_sheet.dart';
import 'package:bambuddy_mobile/features/maintenance/maintenance_providers.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/data/inventory_repository.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:bambuddy_mobile/wear/wear_shape.dart';
import 'package:bambuddy_mobile/wear/wear_transport.dart';
import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watch_connectivity/watch_connectivity.dart';

export 'package:app_test_kit/app_test_kit.dart';
export 'package:bambuddy_mobile/core/auth/credentials_store.dart'
    show InMemoryCredentialsStore;

/// Printer firmware kept off the network: the card reads it while it renders. See
/// "The inert overrides" in docs/test-harness.md.
final inertFirmwareOverride = printerFirmwareProvider.overrideWith(
  (ref, id) => null,
);

/// No announcements: the dashboard reads the inbox for its drawer dot and banner.
final inertAnnouncementsOverride = announcementsProvider.overrideWith(
  _InertAnnouncements.new,
);

class _InertAnnouncements extends AnnouncementsNotifier {
  @override
  Future<AnnouncementFeed> build() async => AnnouncementFeed.hidden;
}

/// No total print time: the printer card reads it from the maintenance overview.
final inertTotalPrintHoursOverride = printerTotalPrintHoursProvider
    .overrideWith((ref, id) => null);

/// The chamber ceiling at 60, which is what an unknown version resolves to, so
/// gauges and sliders behave as before the probe lands.
final inertChamberMaxOverride = chamberMaxTargetProvider.overrideWithValue(60);

/// History shortcuts on, as any current server answers.
final inertHistorySupportOverrides = [
  heaterHistorySupportedProvider.overrideWithValue(const AsyncData(true)),
  amsHistorySupportedProvider.overrideWithValue(const AsyncData(true)),
];

/// The Polish strings the tests assert on. Finders read their text from here,
/// never from a literal, so a copy change does not touch the tests.
final pl = lookupAppLocalizations(const Locale('pl'));

/// The English strings, for the code that renders in the server's language or
/// the system's rather than the app's forced `pl`.
final en = lookupAppLocalizations(const Locale('en'));

/// Wraps a widget in a MaterialApp forced to Polish, the language the tests
/// assert. [builder] goes to `MaterialApp.builder`, above the navigator: the only
/// place an inherited widget reaches a pushed route or a dialog as well as `home`.
Widget plApp(Widget child, {TransitionBuilder? builder}) => MaterialApp(
  locale: const Locale('pl'),
  localizationsDelegates: _plDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: builder,
  home: child,
);

/// [plApp] for a screen reached through a router (`context.go`, deep links).
Widget plRouterApp(
  RouterConfig<Object> routerConfig, {
  TransitionBuilder? builder,
}) => MaterialApp.router(
  locale: const Locale('pl'),
  localizationsDelegates: _plDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: builder,
  routerConfig: routerConfig,
);

final _plDelegates = [
  AppLocalizations.delegate,
  ReportLocalizations.delegate,
  ...GlobalMaterialLocalizations.delegates,
];

/// Pumps a phone widget inside a `ProviderScope` and [plApp]. Almost every caller
/// wants [noServerProfileOverride] in [overrides].
Future<void> pumpPhone(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const [],
  TransitionBuilder? builder,
}) => tester.pumpWidget(
  ProviderScope(
    retry: neverRetry,
    overrides: overrides,
    child: plApp(child, builder: builder),
  ),
);

/// Pumps a wear widget with mock preferences, an in-memory credentials store and
/// a handle on the container. [wrapInApp] is false for `WearApp`, which builds its
/// own `MaterialApp`. The scope owns the container on purpose; see docs/test-harness.md.
Future<ProviderContainer> pumpWear(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const [],
  bool wrapInApp = true,
  WearShape shape = WearShape.round,
  Size face = wearFaceSmall,
}) async {
  useWatchFace(tester, shape, face);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  late ProviderContainer container;
  await tester.pumpWidget(
    ProviderScope(
      retry: neverRetry,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        credentialsStoreProvider.overrideWithValue(InMemoryCredentialsStore()),
        ...overrides,
      ],
      child: Builder(
        builder: (context) {
          container = ProviderScope.containerOf(context, listen: false);
          return wrapInApp ? plApp(child, builder: wearShapeBuilder) : child;
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// [WearShapeScope] where `WearApp` puts it, above the navigator, so a dialog or
/// pushed route reads the same shape as its screen. See docs/test-harness.md.
Widget wearShapeBuilder(BuildContext context, Widget? child) =>
    WearShapeScope(child: child!);

/// The button the diagnostic [id] tags, whichever [ButtonStyleButton] it is —
/// filled, outlined or text — so a test asks for the id, not the kind.
ButtonStyleButton buttonAt(WidgetTester tester, String id) => tester.widget(
  find.descendant(
    of: byLogId(id),
    matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
  ),
);

/// A window of [size] logical pixels at density 1, given back with the test.
void useLogicalWindow(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
}

/// The phones a landscape screen (the controller, wall mode) is designed for:
/// the reporter's Redmi 9T Pro and a 20:9 Pixel-class phone, in dp.
const landscapeRedmi = Size(891, 411);
const landscapePixel = Size(915, 412);

/// Answers what a landscape screen asks the platform on entry and exit — the
/// window's keep-screen-on and `SystemChrome` — and hands each call to
/// [onWindow] / [onPlatform] for a test that checks them.
void mockImmersiveChannels(
  WidgetTester tester, {
  void Function(MethodCall call)? onWindow,
  void Function(MethodCall call)? onPlatform,
}) {
  const window = MethodChannel('page.codeberg.morganmlgman.bambuddy/window');
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(window, (call) async {
    onWindow?.call(call);
    return null;
  });
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    onPlatform?.call(call);
    return null;
  });
  addTearDown(() {
    messenger.setMockMethodCallHandler(window, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });
}

/// The two round faces worth testing against, in physical pixels at density 2;
/// the small one is the default (see docs/test-harness.md).
const wearFaceSmall = Size(384, 384);
const wearFaceLarge = Size(450, 450);

/// A real watch instead of the 800x600 phone surface. The shape is answered on
/// [wearShapeChannel] the way the platform answers it.
void useWatchFace(WidgetTester tester, WearShape shape, Size face) {
  tester.view.physicalSize = face;
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    wearShapeChannel,
    (call) async =>
        call.method == 'isScreenRound' ? shape == WearShape.round : null,
  );
  addTearDown(() => messenger.setMockMethodCallHandler(wearShapeChannel, null));
}

/// The channel [WearShapeQuery] talks to, so tests answer the same one the app
/// asks.
const wearShapeChannel = MethodChannel(
  'page.codeberg.morganmlgman.bambuddy/wear_shape',
);

/// Brings [finder] onto the watch face, scrolling the way a user does — into the
/// middle of the face, not merely the viewport. See docs/test-harness.md.
Future<void> revealOnWatch(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      40,
      scrollable: find.byType(Scrollable).first,
    );
  }
  // The rim of a curved list is on screen but neither readable nor hittable.
  await Scrollable.ensureVisible(
    finder.evaluate().first,
    alignment: 0.5,
    duration: Duration.zero,
  );
  await tester.pumpAndSettle();
}

/// Fails unless every corner of [finder]'s box is on the round face's glass. For
/// anything the layout places itself rather than `WearScrollView`; see docs/test-harness.md.
void expectOnGlass(WidgetTester tester, Finder finder, {String? reason}) {
  final face = tester.view.physicalSize / tester.view.devicePixelRatio;
  final centre = Offset(face.width / 2, face.height / 2);
  final radius = face.shortestSide / 2;
  final box = tester.getRect(finder);
  for (final corner in [
    box.topLeft,
    box.topRight,
    box.bottomLeft,
    box.bottomRight,
  ]) {
    expect(
      (corner - centre).distance,
      lessThanOrEqualTo(radius),
      reason: reason ?? 'corner $corner of $box is off a ${radius * 2} dp face',
    );
  }
}

/// [revealOnWatch] and then tap: settles the scroll, pumps one frame after the tap.
Future<void> tapOnWatch(WidgetTester tester, Finder finder) async {
  await revealOnWatch(tester, finder);
  await tester.tap(finder);
  await tester.pump();
}

/// The phone→watch handoff, faked: what the Data Layer has latched, what it
/// pushes live, and whether persisting the result works.
class FakeWatchConfigSync extends WatchConfigSync {
  FakeWatchConfigSync({
    this.pending,
    StreamController<WatchConfig>? pushes,
    this.failsToApply = false,
    this.applyGate,
    this.pendingGate,
  }) : pushes = pushes ?? StreamController<WatchConfig>.broadcast(),
       super(
         watch: WatchConnectivity(),
         credentials: InMemoryCredentialsStore(),
       );

  /// What the phone has latched — what [latestPending] answers.
  final WatchConfig? pending;

  /// Live pushes. Add to it to act as a phone that pushed while the app is open.
  final StreamController<WatchConfig> pushes;

  /// Make [apply] throw, the way secure storage does when the Keystore no longer
  /// holds the key the secrets were written with.
  final bool failsToApply;

  /// When set, [apply] does not finish until the test completes it — that is how
  /// a write still in flight is held open while the screen goes away.
  final Completer<void>? applyGate;

  /// When set, [latestPending] does not answer until the test completes it —
  /// the cold-start read still on its way while a live push lands.
  final Completer<void>? pendingGate;

  /// Every config [apply] was asked to persist, in order.
  final applied = <WatchConfig>[];

  @override
  Future<WatchConfig?> latestPending() async {
    await pendingGate?.future;
    return pending;
  }

  @override
  Stream<WatchConfig> configStream() => pushes.stream;

  @override
  Future<void> apply(WatchConfig config) async {
    applied.add(config);
    if (failsToApply) throw Exception('keystore is gone');
    if (applyGate != null) await applyGate!.future;
  }
}

/// `inventoryBackendProvider` fixed to [backend]; the real one asks the
/// server's `/spoolman/status`, which a test would otherwise have to mock.
/// [base] with every provider that [top] overrides taken from [top] instead. A
/// harness lists its defaults and lets a test replace any of them; Riverpod 2 let
/// the later duplicate win, Riverpod 3 refuses the container
/// ("Tried to override a provider twice").
List<Override> layerOverrides(List<Override> base, List<Override> top) {
  final replaced = {for (final o in top) o.origin};
  return [...base.where((o) => !replaced.contains(o.origin)), ...top];
}

/// [next] as a notifier's `state` reports it while [previous] was showing: the
/// framework attaches the old value itself when `state = AsyncLoading()` is
/// assigned, but only through `copyWithPrevious`, which is internal API. A test
/// of something that only *reads* such a state builds it here, once.
AsyncValue<T> reportedOver<T>(AsyncValue<T> next, AsyncValue<T> previous) =>
    // ignore: invalid_use_of_internal_member
    next.copyWithPrevious(previous, isRefresh: false);

Override inventoryBackendOverride([
  InventoryBackend backend = InventoryBackend.native,
]) => inventoryBackendProvider.overrideWith((ref) => backend);

/// `inventoryRepositoryProvider` over an inert source of [backend] — for code
/// that only asks the repository which backend it runs, in a test with no
/// server profile to build the real one from.
Override inventoryRepositoryOf(InventoryBackend backend) =>
    inventoryRepositoryProvider.overrideWithValue(
      InventoryRepository(switch (backend) {
        InventoryBackend.native => NativeInventorySource(Dio()),
        InventoryBackend.spoolman => SpoolmanInventorySource(Dio()),
      }),
    );

/// `serverProfileProvider` answering with [profile], or "nothing configured yet"
/// when it is null.
Override serverProfileOverride([ServerProfile? profile]) =>
    serverProfileProvider.overrideWith(() => _FixedServerProfile(profile));

/// No server configured, so nothing can be fetched. Not optional in a widget test
/// that renders anything reading the profile; see docs/test-harness.md.
final noServerProfileOverride = serverProfileOverride();

/// The fake server, reached over [authMode], which screens and interceptors act on.
Override fakeServerProfileOverride({AuthMode authMode = AuthMode.none}) =>
    serverProfileOverride(
      ServerProfile(baseUrl: fakeServerBaseUrl, authMode: authMode),
    );

/// The media credential every thumbnail, cover and photo URL is built with —
/// stubbed so a widget test renders the `Image.network` instead of the
/// placeholder it shows while the mint is in flight.
Override mediaAuthOverride({String token = 'tok'}) =>
    mediaAuthProvider.overrideWith((ref) async => MediaAuth(queryToken: token));

/// `serverSettingsProvider` answering with [settings] and never touching the
/// network — what a screen that only reads a flag or the currency out of it
/// wants, since building the real one needs an API client and a profile.
Override serverSettingsOverride(Map<String, dynamic> settings) =>
    serverSettingsProvider.overrideWith(() => _FixedServerSettings(settings));

class _FixedServerSettings extends ServerSettingsNotifier {
  _FixedServerSettings(this._settings);

  final Map<String, dynamic> _settings;

  @override
  Future<Map<String, dynamic>> build() async => _settings;

  @override
  Future<void> refresh() async {}
}

class _FixedServerProfile extends ServerProfileNotifier {
  _FixedServerProfile(this._profile);

  final ServerProfile? _profile;

  @override
  ServerProfile? build() => _profile;
}

/// The archive list a screen renders, with nothing behind it.
Override archiveListOverride(List<Archive> archives) =>
    archiveProvider.overrideWith(() => _FixedArchiveList(archives));

class _FixedArchiveList extends ArchiveNotifier {
  _FixedArchiveList(this._archives);

  final List<Archive> _archives;

  @override
  Future<List<Archive>> build() async => _archives;
}

/// The watch's other side, faked: a fixed [fleet] for every poll, a log of every
/// command that went through, and optionally one [error] thrown by all of it.
/// Every method is logged as `name` / `name:printerId`; assert the whole [calls]
/// list so a stray command shows up.
class FakeWearTransport implements WearTransport {
  FakeWearTransport({
    this.fleet = const WearFleet(printers: []),
    this.fleetAfterClear,
    this.error,
    this.serverVersion,
  });

  /// What every `getFleet` answers.
  final WearFleet fleet;

  /// What `getFleet` answers once `clearHmsErrors` has run — the printer that
  /// stopped reporting its fault. Null keeps [fleet]: a fault that stayed.
  final WearFleet? fleetAfterClear;
  bool _cleared = false;

  /// Thrown by every call when set — the phone refusing, or out of reach.
  final Exception? error;

  /// What every `getServerVersion` answers; `null` is the unknown a phone too
  /// old for the action leaves behind.
  final String? serverVersion;

  /// Every call in order, oldest first — the reads included, which is what the
  /// transport's own tests are about.
  final List<String> calls = [];

  /// The commands only, without the reads a screen runs on mount and again
  /// after every action. This is what a screen test means by "what did the
  /// watch send", and it still shows a stray command rather than swallowing
  /// it.
  List<String> get commands => [
    for (final call in calls)
      if (call != 'getFleet' && call != 'getServerVersion') call,
  ];

  Future<T> _log<T>(String call, T value) {
    calls.add(call);
    final e = error;
    if (e != null) throw e;
    return Future.value(value);
  }

  @override
  Future<WearFleet> getFleet() =>
      _log('getFleet', _cleared ? fleetAfterClear ?? fleet : fleet);

  @override
  Future<String?> getServerVersion() => _log('getServerVersion', serverVersion);

  @override
  Future<void> pause(int printerId) => _log('pause:$printerId', null);

  @override
  Future<void> resume(int printerId) => _log('resume:$printerId', null);

  @override
  Future<void> stop(int printerId) => _log('stop:$printerId', null);

  @override
  Future<void> clearPlate(int printerId) => _log('clearPlate:$printerId', null);

  @override
  Future<void> startNext(int printerId) => _log('startNext:$printerId', null);

  @override
  Future<void> clearHmsErrors(int printerId) {
    _cleared = true;
    return _log('clearHmsErrors:$printerId', null);
  }

  @override
  Future<void> executeHmsAction(
    int printerId, {
    required String printError,
    required String action,
    String? jobId,
  }) => _log(
    'executeHmsAction:$printerId:$printError:$action:${jobId ?? ''}',
    null,
  );
}

/// The notification plugin, faked: every alert recorded as a map, every ongoing
/// update counted, and knobs for the two things a test steers.
class RecordingNotifications implements NotificationService {
  /// Every [showAlert], in order. Read a field by key.
  final List<Map<String, Object?>> alerts = [];

  /// Just the notification ids, for the tests that only care which alert was
  /// raised rather than what it said.
  List<int> get postedIds => [for (final a in alerts) a['id']! as int];

  int ongoingCount = 0;
  int clearCount = 0;
  String? lastTitle;
  String? lastBody;
  int? lastProgress;

  /// Whether the last bar was the indeterminate one (a null progress).
  bool get lastIndeterminate => _lastWasIndeterminate;
  bool _lastWasIndeterminate = false;

  /// Thrown by [showAlert] when set — the platform channel refusing.
  Object? failWith;

  /// What [isAlertActive] answers: whether the alert is still on screen, which
  /// is what gates a silent re-post of the finish photo.
  bool alertActive = true;

  @override
  Future<void> init() async {}

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> showOngoing({
    required String title,
    required String body,
    required int? progress,
  }) async {
    ongoingCount++;
    lastTitle = title;
    lastBody = body;
    lastProgress = progress;
    _lastWasIndeterminate = progress == null;
  }

  @override
  Future<void> clearOngoing() async => clearCount++;

  @override
  Future<void> showAlert({
    required NotifEvent event,
    required int printerId,
    required int id,
    required String title,
    required String body,
    String? payload,
    List<NotificationAction>? actions,
    AlertPicture? picture,
    bool quiet = false,
  }) async {
    alerts.add({
      'event': event,
      'printerId': printerId,
      'id': id,
      'title': title,
      'body': body,
      'payload': payload,
      'actions': actions,
      'actionIds': [for (final a in actions ?? const []) a.id],
      'photo': picture?.photoPath,
      'thumb': picture?.thumbnailPath,
      'quiet': quiet,
    });
    final failure = failWith;
    if (failure != null) throw failure;
  }

  @override
  Future<bool> isAlertActive(int id) async => alertActive;
}

/// `currentUserProvider` answering with [user], or "nobody signed in" when null.
/// `refresh()` is stubbed so a screen calling it after a write stays off the
/// network.
Override currentUserOverride([CurrentUser? user]) =>
    currentUserProvider.overrideWith(() => _FixedCurrentUser(user));

class _FixedCurrentUser extends CurrentUserNotifier {
  _FixedCurrentUser(this._user);

  final CurrentUser? _user;

  @override
  Future<CurrentUser?> build() async => _user;

  @override
  Future<void> refresh() async {}
}

/// The user list a screen renders, with nothing behind it.
Override usersListOverride(List<CurrentUser> users) =>
    usersListProvider.overrideWith(() => _FixedUsersList(users));

class _FixedUsersList extends UsersListNotifier {
  _FixedUsersList(this._users);

  final List<CurrentUser> _users;

  @override
  Future<List<CurrentUser>> build() async => _users;
}

/// Printer statuses that never arrive: the dashboard renders from the printer
/// list alone and no WebSocket or poll is started.
final inertStatusesOverride = printerStatusesProvider.overrideWith(
  _InertStatuses.new,
);

class _InertStatuses extends PrinterStatusesNotifier {
  @override
  Map<int, PrinterStatus> build() => const {};
}

/// A background monitor that never runs: the dashboard touches it on its first
/// frame, and the real one reaches for a platform channel.
final inertBackgroundMonitorOverride = backgroundMonitorProvider
    .overrideWithValue(_InertBackgroundMonitor());

class _InertBackgroundMonitor implements BackgroundMonitor {
  @override
  Future<bool> start() async => false;
  @override
  Future<bool> stop() async => false;
  @override
  Future<bool> isRunning() async => false;
  @override
  void sync(BackgroundSync what) {}
}

/// No smart plugs, so the card's power row stays out of the way and its 5 s
/// poll never starts — a live one outlives the test and trips the pending-timer
/// check.
final inertSmartPlugsOverride = smartPlugsProvider.overrideWith(
  _InertSmartPlugs.new,
);

class _InertSmartPlugs extends SmartPlugsNotifier {
  @override
  SmartPlugsState build() => const SmartPlugsState();
}

/// An [Archive] row for a test that does not care what it says: a finished print
/// with no media. Name only what the test is about.
Archive testArchive({
  int id = 1,
  String filename = 'benchy.gcode.3mf',
  String status = 'completed',
  String? printName = 'Benchy',
  int? printerId,
  String? timelapsePath,
  List<String> photos = const [],
  DateTime? completedAt,
  DateTime? createdAt,
  bool confirmRequested = false,
  PrintVerdict? userVerdict,
  String? userVerdictSource,
}) => Archive(
  id: id,
  filename: filename,
  status: status,
  printName: printName,
  printerId: printerId,
  timelapsePath: timelapsePath,
  photos: photos,
  completedAt: completedAt,
  createdAt: createdAt,
  confirmRequested: confirmRequested,
  userVerdict: userVerdict,
  userVerdictSource: userVerdictSource,
);

/// A recorder wired the way the app wires one, memory-only unless [directory] is
/// given. The redactor and the two ceilings are the app's, not the test's.
DiagnosticRecorder testRecorder({
  DiagnosticsSessionStore? sessions,
  SessionFacts facts = const SessionFacts(
    app: '0.12.1+1201000',
    extra: {'flavor': 'mobile'},
  ),
  Future<Directory?> Function()? directory,
}) => DiagnosticRecorder(
  sessions: sessions ?? MemorySessionStore(),
  redactor: bambuddyRedactor,
  loadFacts: () async => facts,
  sessionDuration: recordingLimit,
  sessionBytes: recordingSizeLimit,
  resolveDirectory: directory ?? () async => null,
);

/// A [PrinterCommandsRepository] that records every call as `kind:args`
/// (`pause:1`, `amsLoad:1:3:-`) and succeeds, unless told otherwise: [gate]
/// holds every call and [error] fails every call, while [holds] and [errors]
/// do the same for one kind only — the part of the tag before the first `:`.
class RecordingCommands implements PrinterCommandsRepository {
  final List<String> calls = [];
  Object? error;
  Completer<void>? gate;
  final holds = <String, Completer<void>>{};
  final errors = <String, Object>{};

  Future<void> _do(String tag) async {
    calls.add(tag);
    final kind = tag.split(':').first;
    await (holds[kind] ?? gate)?.future;
    final failure = errors[kind] ?? error;
    if (failure != null) throw failure;
  }

  @override
  Future<Object?> fetchOpenApi() async => null;
  @override
  Future<void> pause(int id) => _do('pause:$id');
  @override
  Future<void> resume(int id) => _do('resume:$id');
  @override
  Future<void> stop(int id) => _do('stop:$id');
  @override
  Future<void> clearPlate(int id) => _do('clearPlate:$id');
  @override
  Future<void> setChamberLight(int id, {required bool on}) =>
      _do('light:$id:$on');
  @override
  Future<void> setPrintSpeed(int id, int mode) => _do('speed:$id:$mode');
  @override
  Future<void> setNozzleTemperature(int id, int target, {int nozzle = 0}) =>
      _do('nozzle:$id:$target:$nozzle');
  @override
  Future<void> setBedTemperature(int id, int target) => _do('bed:$id:$target');
  @override
  Future<void> setChamberTemperature(int id, int target) =>
      _do('chamber:$id:$target');
  @override
  Future<void> setAirductMode(int id, {required bool heating}) =>
      _do('airduct:$id:$heating');
  @override
  Future<void> setFanSpeed(int id, String fan, int speed) =>
      _do('fan:$id:$fan:$speed');
  @override
  Future<void> selectExtruder(int id, int extruder) =>
      _do('extruder:$id:$extruder');
  @override
  Future<void> startDrying(
    int id, {
    required int amsId,
    required int temp,
    required int duration,
    String filament = '',
  }) => _do('dryStart:$id:$amsId:$temp:$duration:$filament');
  @override
  Future<void> stopDrying(int id, {required int amsId}) =>
      _do('dryStop:$id:$amsId');
  @override
  Future<void> bedJog(int id, double distance, {bool force = false}) =>
      _do('bedJog:$id:$distance:$force');
  @override
  Future<void> xyJog(int id, {double x = 0, double y = 0}) =>
      _do('xyJog:$id:$x:$y');
  @override
  Future<void> extruderJog(int id, double distance) =>
      _do('extruderJog:$id:$distance');
  @override
  Future<void> homeAxes(int id) => _do('homeAxes:$id');
  @override
  Future<void> refreshStatus(int id) => _do('refreshStatus:$id');
  @override
  void nudgeRepublish(Iterable<int> ids) {
    for (final id in ids) {
      unawaited(refreshStatus(id).catchError((Object _) {}));
    }
  }

  @override
  Future<void> amsLoad(int id, int trayId, {int? extruderId}) =>
      _do('amsLoad:$id:$trayId:${extruderId ?? '-'}');
  @override
  Future<void> amsUnload(int id, {int? trayId}) =>
      _do('amsUnload:$id:${trayId ?? '-'}');
  @override
  Future<void> refreshAmsSlot(
    int id, {
    required int amsId,
    required int slotId,
  }) => _do('amsRfid:$id:$amsId:$slotId');
  @override
  Future<void> clearHmsErrors(int id) => _do('hmsClear:$id');
  @override
  Future<void> executeHmsAction(
    int id, {
    required String printError,
    required String action,
    String? jobId,
  }) => _do('hmsAction:$id:$printError:$action:${jobId ?? ''}');
}

/// The inventory screens read the shelf through this: exactly [state], with no
/// server behind it. Anything a test needs to record or refuse is a subclass of
/// `InventoryNotifier` of its own; a shelf that only stands there is this.
class FixedInventory extends InventoryNotifier {
  FixedInventory(this._state);

  final InventoryState _state;

  @override
  Future<InventoryState> build() async => _state;
}

/// `dashboardProvider` fixed at [state], with polling switched off — what a
/// screen that lists printers wants, since the real one polls the server.
Override fixedDashboardOverride([
  DashboardState state = const DashboardState(),
]) => dashboardProvider.overrideWith(() => FixedDashboard(state));

class FixedDashboard extends DashboardNotifier {
  FixedDashboard(this._fixed);

  final DashboardState _fixed;

  @override
  DashboardState build() => _fixed;

  @override
  Future<void> refresh() async {}

  /// What a poll does when the session is rejected and cannot be renewed.
  void expire() => state = const DashboardState(authExpired: true);
}

/// The status REST hands back after a clear: one answer per read, the last one
/// repeated. A `null` is a status the app could not read.
class StatusReadBack extends PrintersRepository {
  StatusReadBack(this._answers) : super(Dio());

  final List<PrinterStatus?> _answers;
  int reads = 0;

  @override
  Future<PrinterStatus?> fetchStatus(int printerId) async =>
      _answers[reads++ < _answers.length ? reads - 1 : _answers.length - 1];
}
