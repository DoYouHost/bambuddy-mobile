import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bambuddy_mobile/core/auth/credentials_store.dart';
import 'package:bambuddy_mobile/core/models/archive.dart';
import 'package:bambuddy_mobile/core/models/current_user.dart';
import 'package:bambuddy_mobile/core/notifications/notification_prefs.dart';
import 'package:bambuddy_mobile/core/notifications/notification_service.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/core/watch/watch_config_sync.dart';
import 'package:bambuddy_mobile/features/archive/archive_providers.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/features/admin/users_providers.dart';
import 'package:bambuddy_mobile/features/dashboard/firmware_providers.dart';
import 'package:bambuddy_mobile/features/dashboard/smart_plugs_providers.dart';
import 'package:bambuddy_mobile/features/dashboard/ws_providers.dart';
import 'package:bambuddy_mobile/features/dashboard/widgets/ams_history_sheet.dart';
import 'package:bambuddy_mobile/features/dashboard/widgets/heater_history_sheet.dart';
import 'package:bambuddy_mobile/features/maintenance/maintenance_providers.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:bambuddy_mobile/wear/wear_shape.dart';
import 'package:bambuddy_mobile/wear/wear_transport.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watch_connectivity/watch_connectivity.dart';

/// Hands the app a temporary directory the test owns, so whatever a download
/// leaves in the cache can be listed afterwards.
///
/// Assign it to `PathProviderPlatform.instance` in `setUp` and delete the
/// directory in `tearDown`; there is nothing to restore, the app reads the
/// instance on every call.
class TempDirProvider extends PathProviderPlatform {
  TempDirProvider(this.path);

  final String path;

  @override
  Future<String?> getTemporaryPath() async => path;
}

/// Inert firmware for widget tests: the printer card reads firmware while it
/// renders and the tests do not assert on it — null keeps the fetch off the
/// network, which otherwise leaves a hanging Dio timer and fails the test.
final inertFirmwareOverride = printerFirmwareProvider.overrideWith(
  (ref, id) => null,
);

/// Inert total print time for widget tests: the printer card reads it from the
/// maintenance overview while it renders. Null keeps that off the network, the
/// same trap as [inertFirmwareOverride].
final inertTotalPrintHoursOverride = printerTotalPrintHoursProvider
    .overrideWith((ref, id) => null);

/// Inert chamber ceiling for widget tests. The temperature tiles read the
/// server's `MAX_CHAMBER_TEMP_C` at render time, which otherwise hits
/// `/updates/version` and leaves a hanging Dio timer — the same trap as
/// [inertFirmwareOverride]. 60 is what an unknown version resolves to anyway,
/// so gauges and sliders behave exactly as they do before the probe lands.
final inertChamberMaxOverride = chamberMaxTargetProvider.overrideWith(
  (ref) async => 60,
);

/// Inert history gating for widget tests. The temperature tiles and the AMS
/// humidity/temperature chips ask whether the server keeps history, which reads
/// the server version over the network — the same hanging-timer trap as
/// [inertFirmwareOverride]. `true` is what any current server answers, so the
/// shortcuts render exactly as they do in the app.
final inertHistorySupportOverrides = [
  heaterHistorySupportedProvider.overrideWith((ref) async => true),
  amsHistorySupportedProvider.overrideWith((ref) async => true),
];

/// Wraps a widget in a MaterialApp with Polish localization — the tests assert
/// Polish strings, so the locale is forced to `pl`.
///
/// [builder] goes to `MaterialApp.builder`, which is above the navigator: that is
/// the only place an inherited widget reaches a pushed route or a dialog as well
/// as `home`.
Widget plApp(Widget child, {TransitionBuilder? builder}) => MaterialApp(
  locale: const Locale('pl'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: builder,
  home: child,
);

/// Pumps a fixed span in place of `pumpAndSettle`, for the screens it can never
/// finish on: a search field's cursor blinks forever, so no frame is ever free
/// of animation and settling waits for one that will not come.
///
/// Three frames of 350 ms — long enough for a sheet, a dialog or a snack to
/// finish opening, which is what every caller is actually waiting for. Written
/// out in five test files before it lived here, and it is the kind of thing
/// that gets copied with one frame fewer.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 350));
  }
}

/// Pumps a phone widget inside a `ProviderScope` and [plApp].
///
/// The counterpart to [pumpWear], which existed while the phone side wrote the
/// same three lines out 27 times. [builder] goes to `MaterialApp.builder`, the
/// only place an inherited widget reaches a pushed route or a dialog.
///
/// Almost every caller wants [noServerProfileOverride] in [overrides]: a widget
/// that reads the profile builds its API client from it, and without one that
/// throws `UnimplementedError` into an unbounded `ErrorWidget` whose overflow
/// buries whatever the test was about.
Future<void> pumpPhone(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const [],
  TransitionBuilder? builder,
}) => tester.pumpWidget(
  ProviderScope(
    overrides: overrides,
    child: plApp(child, builder: builder),
  ),
);

/// Pumps a wear widget with what every wear test needs anyway: mock preferences,
/// an in-memory credentials store, and a handle on the container so a test can
/// read or seed providers.
///
/// [wrapInApp] is false for `WearApp`, which builds its own `MaterialApp` (and
/// therefore runs in the system locale, not `plApp`'s Polish); every other wear
/// widget needs the harness to have localizations at all.
///
/// The scope owns the container on purpose, rather than the test holding one and
/// handing it over: `wearFleetProvider` runs a poll timer, and a container that
/// outlives the widget tree keeps that timer alive past the end of the test —
/// which trips the framework's pending-timer check. Tearing the tree down
/// disposes the container, which cancels it.
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

/// [WearShapeScope] where `WearApp` puts it — above the navigator, so a dialog
/// or a pushed route reads the same shape as the screen that opened it.
///
/// Wrapping the *child* instead leaves the scope under `home`, and a route is
/// `home`'s sibling rather than its descendant: every dialog then silently fell
/// back to round, which is the one shape a test asking for a square face is not
/// looking for.
Widget wearShapeBuilder(BuildContext context, Widget? child) =>
    WearShapeScope(child: child!);

/// The two round faces worth testing against, in physical pixels at density 2.
///
/// The small one is the default here on purpose: it is what Wear emulators boot
/// with and what the smaller watches ship, and it is where a size written as a
/// number instead of a fraction of the display breaks — the confirm dialog's
/// button row fit 225 dp and overflowed 192 dp by 11 px, with every test green.
const wearFaceSmall = Size(384, 384);
const wearFaceLarge = Size(450, 450);

/// A real watch instead of the 800x600 phone surface every widget test defaults
/// to: the round-safe layout only means anything against a face this small.
///
/// The shape is answered on `MainActivity`'s `wear_shape` channel, the way the
/// platform answers it on a device.
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

/// Brings [finder] onto the watch face, scrolling the screen if it has to.
///
/// On a 225 dp face most of a wear screen starts below the fold, and a
/// `ListView` does not build what is off-screen at all — so a finder that used
/// to match on the 800x600 default test surface now matches nothing until the
/// screen is scrolled. Reaching for a control the way a user does is the point:
/// it is the same scroll Google Play's reviewer had to make.
Future<void> revealOnWatch(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      40,
      scrollable: find.byType(Scrollable).first,
    );
  }
  // Into the *middle* of the face, not merely into the viewport. A curved list
  // runs all the way to the rim, so "on screen" now includes the last few
  // degrees of the circle, where an item is scaled almost to nothing — existing
  // there is not the same as being readable or hittable, and `scrollUntilVisible`
  // stops at the first of those. A user scrolls what they want to the centre.
  await Scrollable.ensureVisible(
    finder.evaluate().first,
    alignment: 0.5,
    duration: Duration.zero,
  );
  await tester.pumpAndSettle();
}

/// Fails unless every corner of [finder]'s box is on the round face's glass.
///
/// The check no wear test had, and the one the snackbar walked straight past: a
/// widget test is happy as long as nothing overflows the *square* the display
/// reports, while the watch only ever lights the circle inscribed in it. A bar
/// pinned to the bottom of that square is not an overflow — it is simply mostly
/// invisible, on the device and nowhere else.
///
/// Reach for it on anything the layout places rather than the scroll view: what
/// goes through `WearScrollView` is already inside the glass by construction.
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

/// [revealOnWatch] and then tap, for the controls a test drives rather than
/// asserts on.
///
/// Settles the scroll before the tap but only pumps one frame after it: what a
/// tap starts is the test's business, and a watch action that puts a spinner up
/// would hang `pumpAndSettle` forever.
Future<void> tapOnWatch(WidgetTester tester, Finder finder) async {
  await revealOnWatch(tester, finder);
  await tester.tap(finder);
  await tester.pump();
}

/// Loads a fixture from test/fixtures/ — the path is relative to the package
/// root, which is where `flutter test` runs from.
dynamic readFixture(String name) => jsonDecode(readFixtureString(name));

/// A fixture's raw contents, for the parsers that take text (WS frames, say).
String readFixtureString(String name) =>
    File('test/fixtures/$name').readAsStringSync();

/// The phone→watch handoff, faked, with knobs for every shape the wear tests
/// need: what the Data Layer has latched, what it pushes live, and whether
/// persisting the result works.
///
/// One fake rather than one per test file: three of them had grown, each
/// re-deriving the same `super(...)` and stubbing a different third of the API.
class FakeWatchConfigSync extends WatchConfigSync {
  FakeWatchConfigSync({
    this.pending,
    StreamController<WatchConfig>? pushes,
    this.failsToApply = false,
    this.applyGate,
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

  /// Every config [apply] was asked to persist, in order.
  final applied = <WatchConfig>[];

  @override
  Future<WatchConfig?> latestPending() async => pending;

  @override
  Stream<WatchConfig> configStream() => pushes.stream;

  @override
  Future<void> apply(WatchConfig config) async {
    applied.add(config);
    if (failsToApply) throw Exception('keystore is gone');
    if (applyGate != null) await applyGate!.future;
  }
}

/// An in-memory CredentialsStore, so the core tests never touch the plugin.
class InMemoryCredentialsStore implements CredentialsStore {
  String? jwt;
  String? apiKey;
  String? username;
  String? password;

  @override
  Future<String?> readJwt() async => jwt;

  @override
  Future<void> writeJwt(String token) async => jwt = token;

  @override
  Future<String?> readApiKey() async => apiKey;

  @override
  Future<void> writeApiKey(String key) async => apiKey = key;

  @override
  Future<({String username, String password})?> readRememberedLogin() async {
    final u = username;
    final p = password;
    if (u == null || p == null) return null;
    return (username: u, password: p);
  }

  @override
  Future<void> writeRememberedLogin(String username, String password) async {
    this.username = username;
    this.password = password;
  }

  @override
  Future<void> clearRememberedLogin() async {
    username = null;
    password = null;
  }

  @override
  Future<void> clearAll() async {
    jwt = null;
    apiKey = null;
    username = null;
    password = null;
  }
}

/// Every request that really left the app, oldest first.
///
/// The only honest answer to "what did the app send". An `http_mock_adapter`
/// handler runs **once, when the route is declared** — never when a request
/// arrives — so a counter or a list written inside one records the
/// registration and reports the same thing whether the app sent nothing, one
/// request or ten. Six tests were asserting on such a flag, and two of them
/// passed with the call under test deleted outright.
///
/// An interceptor runs per request, and it runs *before* the adapter looks for
/// a route — so a request to a path no mock covers is logged here and still
/// fails the test, which is what makes this safe to assert on alone.
class RequestLog {
  final List<RequestOptions> requests = [];

  /// The status of each answer, in the order the answers came back — `null`
  /// where the failure carried no response at all, which is what a request no
  /// mocked route matches looks like. Requests fired concurrently can complete
  /// out of order, so this lines up with [calls] only when they were awaited
  /// one at a time; compare it as a set when they were not.
  ///
  /// Worth asserting whenever the code under test swallows what it gets: a
  /// swallow hides the difference between the refusal the test registered and
  /// the adapter failing to find a route, and both leave the caller looking
  /// identical from outside.
  final List<int?> statuses = [];

  /// `METHOD /path`, which is what a test asking "did it hit the right route"
  /// actually means. Assert the whole list, not a `contains`: a stray request
  /// then shows up instead of passing unnoticed.
  List<String> get calls => [for (final r in requests) '${r.method} ${r.path}'];

  /// The most recent request — its `data` is the body a write test asserts on,
  /// its `queryParameters` the query a read test does.
  RequestOptions get last => requests.last;

  /// Just the paths, for a test about which endpoints were reached and in what
  /// order rather than what they carried.
  List<String> get paths => [for (final r in requests) r.path];

  /// Waits until [count] requests have *finished*, for the fire-and-forget
  /// calls a repository starts with `unawaited`.
  ///
  /// A single `Future.delayed(Duration.zero)` is not enough — the interceptor
  /// chain and the adapter each take their own turn of the event loop, so the
  /// log is still empty when the test asserts. Yielding a bounded number of
  /// turns keeps that deterministic instead of racing a wall-clock delay.
  ///
  /// Counts [statuses], not [requests]: a request is logged on its way out and
  /// its status only once the answer is back, so waiting on the former leaves
  /// the latter empty. Returns on the deadline rather than throwing, so the
  /// caller's own `expect` reports what actually arrived.
  Future<void> untilCount(int count, {int turns = 100}) async {
    for (var i = 0; i < turns && statuses.length < count; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }
}

/// Logs every request [dio] makes into the returned [RequestLog].
///
/// Add it before the act, assert on the log after — see [RequestLog] for why
/// the mock's own handler cannot do this.
RequestLog captureRequests(Dio dio) {
  final log = RequestLog();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        log.requests.add(options);
        handler.next(options);
      },
      onResponse: (response, handler) {
        log.statuses.add(response.statusCode);
        handler.next(response);
      },
      onError: (error, handler) {
        log.statuses.add(error.response?.statusCode);
        handler.next(error);
      },
    ),
  );
  return log;
}

/// The host every test that needs a server talks to. Shared so a Dio adapter
/// and the profile a screen reads cannot drift apart.
const fakeServerBaseUrl = 'http://s.local:8000';

/// A Dio pointed at [fakeServerBaseUrl], which is what a repository test wants
/// before it hangs a `DioAdapter` off it.
///
/// The URL was written out by hand in 45 files while the constant right above
/// had exactly one caller; a screen reading the profile and an adapter mocking
/// the wire have to agree on the host, and two spellings of it is how they stop
/// agreeing.
Dio testDio() => Dio(BaseOptions(baseUrl: fakeServerBaseUrl));

/// `serverProfileProvider` answering with [profile], or with "nothing
/// configured yet" when it is null.
///
/// One factory rather than a `_FakeProfileNotifier` per test file: there were 26
/// of those. Twelve were byte-identical `build() => null`, and every one of the
/// rest but the watch's settings screen pointed at [fakeServerBaseUrl] and
/// differed only in the auth mode.
///
/// The two left with their own are the two that need one: `current_user_provider`
/// drives the profile by hand mid-test, and the watch's settings screen overrides
/// `clear()` to record that it was called.
Override serverProfileOverride([ServerProfile? profile]) =>
    serverProfileProvider.overrideWith(() => _FixedServerProfile(profile));

/// No server configured, so nothing can be fetched — what a test that only
/// renders a screen wants.
///
/// Not optional in a widget test that renders anything reading the profile:
/// building the API client without one throws `UnimplementedError`, the widget
/// becomes an unbounded `ErrorWidget`, and the 100000 px overflow that follows
/// buries whatever the test was actually about.
final noServerProfileOverride = serverProfileOverride();

/// The fake server, reached over [authMode]. The mode is not decoration: screens
/// hide admin-only routes for an API key, and the auth interceptors differ.
Override fakeServerProfileOverride({AuthMode authMode = AuthMode.none}) =>
    serverProfileOverride(
      ServerProfile(baseUrl: fakeServerBaseUrl, authMode: authMode),
    );

class _FixedServerProfile extends ServerProfileNotifier {
  _FixedServerProfile(this._profile);

  final ServerProfile? _profile;

  @override
  ServerProfile? build() => _profile;
}

/// The archive list a screen renders, with nothing behind it: every load
/// answers [archives] and no request is made.
///
/// One factory rather than a `_FakeArchiveNotifier` per test file — there were
/// five, byte-identical down to the field name.
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
///
/// One fake rather than one per test file, the same reasoning as
/// [FakeWatchConfigSync]: four of them had grown — the two screen tests each
/// recording its own third of the API in its own string format, the transport
/// test using it as a stand-in for a whole leg of [HybridWearTransport].
///
/// Every method is implemented and logged as `name` / `name:printerId`, using
/// the real method names, so a stray command shows up in [calls] instead of
/// vanishing into a `noSuchMethod` that only throws for the routes one test
/// happened to think of. Assert the whole list, not a `contains`, and that
/// property holds.
class FakeWearTransport implements WearTransport {
  FakeWearTransport({this.fleet = const WearFleet(printers: []), this.error});

  /// What every `getFleet` answers.
  final WearFleet fleet;

  /// Thrown by every call when set — the phone refusing, or out of reach.
  final Exception? error;

  /// Every call in order, oldest first — [getFleet] included, which is what the
  /// transport's own tests are about.
  final List<String> calls = [];

  /// The commands only, without the fleet polls a screen runs on mount and
  /// again after every action. This is what a screen test means by "what did
  /// the watch send", and it still shows a stray command rather than swallowing
  /// it.
  List<String> get commands => [
    for (final call in calls)
      if (call != 'getFleet') call,
  ];

  Future<T> _log<T>(String call, T value) {
    calls.add(call);
    final e = error;
    if (e != null) throw e;
    return Future.value(value);
  }

  @override
  Future<WearFleet> getFleet() => _log('getFleet', fleet);

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
  Future<void> clearHmsErrors(int printerId) =>
      _log('clearHmsErrors:$printerId', null);

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

/// The notification plugin, faked: every alert recorded as a map, every
/// ongoing update counted, and knobs for the two things a test steers.
///
/// One stub rather than one per test file — there were five, each implementing
/// the same six-method interface and recording a different third of it, so a
/// test that wanted the payload had to grow the stub next door before it could
/// ask. [alerts] carries the **union** of what those five looked at, including
/// both `actions` (the objects) and `actionIds` (their ids), because asserting
/// on the ids is what most callers actually mean.
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
    required int progress,
  }) async {
    ongoingCount++;
    lastTitle = title;
    lastBody = body;
    lastProgress = progress;
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
    });
    final failure = failWith;
    if (failure != null) throw failure;
  }

  @override
  Future<bool> isAlertActive(int id) async => alertActive;
}

/// `currentUserProvider` answering with [user], or with "nobody signed in" when
/// it is null.
///
/// One factory rather than a `_FakeCurrentUser` per test file — there were four
/// across the admin screens, in two shapes that differed only in whether they
/// also stubbed `refresh()`. Stubbing it here covers both: a screen that calls
/// it after a write must not fall through to the network.
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

/// A Dio adapter that answers from a script instead of a socket.
///
/// One class rather than three: two files carried byte-identical copies taking
/// a single [reply], and a third took a list of steps and logged the requests.
/// Both shapes live here — a step may return a `ResponseBody` or a
/// `DioException`, and the exception is thrown rather than returned, which is
/// how a transport failure reaches the code under test.
class ScriptedAdapter implements HttpClientAdapter {
  ScriptedAdapter(Object Function(RequestOptions options) reply)
    : _steps = [reply];

  /// One step per request, in order. The **last step stands for every request
  /// past the end of the script**, so a retry that fires more often than the
  /// test spelled out is answered rather than crashing on a range error.
  ScriptedAdapter.script(this._steps) : assert(_steps.isNotEmpty);

  final List<Object Function(RequestOptions options)> _steps;

  /// Every request that reached the adapter, oldest first — the retry and
  /// refresh tests are about how many there were and what they carried.
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final step = _steps[(requests.length - 1).clamp(0, _steps.length - 1)];
    final answer = step(options);
    if (answer is DioException) throw answer;
    return answer as ResponseBody;
  }

  @override
  void close({bool force = false}) {}
}

/// A [Timer] the test fires by hand, for the code that schedules work instead
/// of doing it.
///
/// One fake rather than three: they differed only in whether they kept the
/// [duration] they were asked for, which is the one thing a test checking *when*
/// something was scheduled needs.
class FakeTimer implements Timer {
  FakeTimer(this.duration, this._callback);

  /// What the code under test asked to wait — assert on it rather than on the
  /// wall clock.
  final Duration duration;
  final void Function() _callback;

  bool cancelled = false;

  /// Runs the callback, unless the code cancelled the timer first.
  void fire() {
    if (!cancelled) _callback();
  }

  @override
  void cancel() => cancelled = true;

  @override
  bool get isActive => !cancelled;

  @override
  int get tick => 0;
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

/// An [Archive] row for a test that needs one but does not care what it says.
///
/// One builder rather than four: three of them built a byte-identical Benchy
/// and differed only in which field they let the test vary, so adding a case
/// meant growing the copy next door first. Defaults describe a finished print
/// with no media; name only what the test is about.
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
);
