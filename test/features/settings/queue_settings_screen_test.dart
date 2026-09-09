import 'dart:async';

import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/current_user.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/data/server_settings_repository.dart';
import 'package:bambuddy_mobile/features/common/settings_rows.dart';
import 'package:bambuddy_mobile/features/settings/queue_settings_screen.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// The screen answers two questions the wire cannot: which rows this server
/// has, and whether this session may write them. Both are gates that fail
/// silently when wrong — an unknown key is written and dropped, a refused write
/// leaves a row reading the opposite of the truth — so both are pinned here.
void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('pl'));
  });

  /// The queue block as a current server answers it. `GET /settings` always
  /// carries every field the schema knows, so a modern server has all of them.
  Map<String, dynamic> modernSettings({
    bool keepWarm = true,
    bool preheat = true,
  }) => {
    'require_plate_clear': false,
    'queue_shortest_first': true,
    'queue_max_concurrent_uploads': 4,
    'preheat_enabled': preheat,
    'preheat_max_wait_seconds': 900,
    'preheat_soak_seconds': 300,
    'queue_keep_bed_warm': keepWarm,
    'queue_keep_warm_bed_temp': 90,
    'queue_keep_warm_max_minutes': 120,
  };

  Future<_FakeSettingsRepo> pumpScreen(
    WidgetTester tester,
    Map<String, dynamic> settings, {
    AuthMode authMode = AuthMode.none,
    AppApiException? failWith,
    CurrentUser? user,
    double viewHeight = 5400,
  }) async {
    // The default 800x600 window builds only the first section of the list,
    // and every gate this file is about sits further down it. A phone-shaped
    // window puts the whole screen on one page.
    usePhoneWindow(tester, dp: viewHeight / 3);

    final repo = _FakeSettingsRepo(settings, failWith: failWith);
    await pumpPhone(
      tester,
      const QueueSettingsScreen(),
      overrides: [
        fakeServerProfileOverride(authMode: authMode),
        currentUserOverride(user),
        serverSettingsRepositoryProvider.overrideWithValue(repo),
      ],
    );
    await tester.pumpAndSettle();
    return repo;
  }

  /// The provider container behind the pumped screen.
  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(
        tester.element(find.byType(QueueSettingsScreen)),
        listen: false,
      );

  /// The switch belonging to the row titled [title].
  Switch switchFor(WidgetTester tester, String title) => tester.widget<Switch>(
    find.descendant(
      of: find.ancestor(of: find.text(title), matching: find.byType(Row)),
      matching: find.byType(Switch),
    ),
  );

  group('what the server has', () {
    testWidgets('a server that knows none of them shows no section at all', (
      tester,
    ) async {
      await pumpScreen(tester, const {'use_slicer_api': true});

      expect(
        find.text(l10n.queueSettingsQueueHeader.toUpperCase()),
        findsNothing,
      );
      expect(
        find.text(l10n.queueSettingsKeepWarmHeader.toUpperCase()),
        findsNothing,
      );
      expect(find.byType(Switch), findsNothing);
      expect(find.byType(Slider), findsNothing);
      // Not a blank grey page: a settings map that came back empty means
      // either an old server or a read that failed, and the user is owed the
      // sentence and a way to retry.
      expect(find.text(l10n.queueSettingsUnavailable), findsOneWidget);
    });

    testWidgets('a modern server shows all three sections', (tester) async {
      await pumpScreen(tester, modernSettings());

      for (final header in [
        l10n.queueSettingsQueueHeader,
        l10n.queueSettingsPreheatHeader,
        l10n.queueSettingsKeepWarmHeader,
      ]) {
        expect(find.text(header.toUpperCase()), findsOneWidget);
      }
      expect(find.text(l10n.queueSettingsKeepWarmTitle), findsOneWidget);
    });

    testWidgets('every slider says what its number changes', (tester) async {
      await pumpScreen(tester, modernSettings());

      // A switch reads on/off; a slider reads "4", which says nothing on its
      // own. "Files uploaded to 2 printers at once" was the row that proved it.
      final sliders = tester.widgetList<SettingsSlider>(
        find.byType(SettingsSlider),
      );
      expect(sliders, hasLength(5));
      for (final slider in sliders) {
        expect(slider.subtitle, isNotNull, reason: slider.tag);
        expect(find.text(slider.subtitle!), findsOneWidget);
      }
    });

    testWidgets('a server with only part of the block shows only that part', (
      tester,
    ) async {
      // Keep-warm without preheat is not a shape any release has, but a partial
      // response is exactly what the per-key gate exists to survive.
      await pumpScreen(tester, const {
        'require_plate_clear': false,
        'queue_keep_bed_warm': false,
        'queue_keep_warm_bed_temp': 90,
      });

      expect(
        find.text(l10n.queueSettingsQueueHeader.toUpperCase()),
        findsOneWidget,
      );
      expect(
        find.text(l10n.queueSettingsKeepWarmHeader.toUpperCase()),
        findsOneWidget,
      );
      expect(
        find.text(l10n.queueSettingsPreheatHeader.toUpperCase()),
        findsNothing,
        reason: 'no preheat key answered, so no preheat row to write',
      );
      expect(
        find.text(l10n.queueSettingsKeepWarmOffNote),
        findsOneWidget,
        reason:
            'the note is about the bed-temperature row, and this server '
            'has that one',
      );
      // The keep-warm section is there, minus the row the server lacks: the
      // bed temperature has a slider, the hold duration has none.
      expect(find.text(l10n.queueSettingsKeepWarmTitle), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
    });
  });

  testWidgets('a note is not shown for rows the server does not have', (
    tester,
  ) async {
    // The master switch without any of the rows under it: an explanation of
    // why those rows are greyed explains nothing when there are none.
    await pumpScreen(tester, const {
      'preheat_enabled': false,
      'queue_keep_bed_warm': false,
    });

    expect(find.text(l10n.queueSettingsPreheatTitle), findsOneWidget);
    expect(find.text(l10n.queueSettingsPreheatOffNote), findsNothing);
    expect(find.text(l10n.queueSettingsKeepWarmTitle), findsOneWidget);
    expect(find.text(l10n.queueSettingsKeepWarmOffNote), findsNothing);
  });

  group('writing', () {
    testWidgets('a switch writes exactly its own key', (tester) async {
      final repo = await pumpScreen(tester, modernSettings());

      await tester.tap(find.text(l10n.queueSettingsKeepWarmTitle));
      await tester.pumpAndSettle();

      expect(repo.writes, [
        {'queue_keep_bed_warm': false},
      ]);
    });

    testWidgets('a refusal puts the switch back and says why', (tester) async {
      final repo = await pumpScreen(
        tester,
        modernSettings(keepWarm: false),
        // A named account the server told us holds everything, and a route that
        // disagrees. That is the case `/auth/me` has been wrong about before.
        authMode: AuthMode.jwt,
        user: const CurrentUser(id: 1, username: 'ola', isAdmin: true),
        failWith: const AuthException(
          AppErrorCode.forbidden,
          detail: 'Missing required permissions: settings:update',
        ),
      );

      expect(
        find.text(l10n.queueSettingsReadOnlyPermission),
        findsNothing,
        reason: 'nothing refused yet, so the form is offered',
      );

      await tester.tap(find.text(l10n.queueSettingsKeepWarmTitle));
      await tester.pumpAndSettle();

      expect(repo.writes, hasLength(1), reason: 'it did try');
      expect(
        find.text(l10n.queueSettingsReadOnlyPermission),
        findsOneWidget,
        reason: 'the refusal closes the form instead of failing every tap',
      );
      final keepWarm = tester.widget<Switch>(
        find.descendant(
          of: find.ancestor(
            of: find.text(l10n.queueSettingsKeepWarmTitle),
            matching: find.byType(Row),
          ),
          matching: find.byType(Switch),
        ),
      );
      expect(
        keepWarm.value,
        isFalse,
        reason: 'reverted to what the server has',
      );
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('dragging a slider writes once, on release', (tester) async {
      final repo = await pumpScreen(tester, modernSettings());

      // Held down and moved, not `drag`, which lifts the finger for you and
      // would assert after the release it is meant to be testing.
      final finger = await tester.startGesture(
        tester.getCenter(find.byType(Slider).first),
      );
      await finger.moveBy(const Offset(60, 0));
      await tester.pump();
      expect(repo.writes, isEmpty, reason: 'still dragging');

      await finger.up();
      await tester.pumpAndSettle();
      expect(repo.writes, hasLength(1));
      expect(repo.writes.single.keys, ['queue_max_concurrent_uploads']);
      expect(
        repo.writes.single['queue_max_concurrent_uploads'],
        greaterThan(4),
        reason: 'dragged right from the 4 the server holds',
      );
    });

    testWidgets('a dependent slider is greyed while its master is off', (
      tester,
    ) async {
      await pumpScreen(tester, modernSettings(preheat: false));

      expect(find.text(l10n.queueSettingsPreheatOffNote), findsOneWidget);
      final sliders = tester
          .widgetList<Slider>(find.byType(Slider))
          .where((s) => s.onChanged == null);
      expect(
        sliders,
        hasLength(2),
        reason: 'the two preheat durations, and nothing else',
      );
    });
  });

  group('one write does not undo another', () {
    testWidgets('a failing write reverts only its own row', (tester) async {
      final repo = await pumpScreen(tester, modernSettings(keepWarm: false));
      // One write left hanging and another failing under it. The first is held
      // open deliberately: letting it finish would refetch the settings and
      // repair the state, hiding the very thing this asserts.
      final holding = Completer<void>();
      repo.gates['require_plate_clear'] = holding;
      repo.failKey = 'queue_keep_bed_warm';

      await tester.tap(find.text(l10n.queueSettingsPlateClearTitle));
      await tester.pump();
      await tester.tap(find.text(l10n.queueSettingsKeepWarmTitle));
      await tester.pumpAndSettle();

      expect(repo.writes, hasLength(2));
      expect(
        switchFor(tester, l10n.queueSettingsPlateClearTitle).value,
        isTrue,
        reason: 'its own write is still on its way; nothing reverted it',
      );
      expect(
        switchFor(tester, l10n.queueSettingsKeepWarmTitle).value,
        isFalse,
        reason: 'the write that failed is the one that goes back',
      );

      holding.complete();
      await tester.pumpAndSettle();
    });
  });

  testWidgets('nothing is writable until the verdict is in', (tester) async {
    // `permissionProvider` answers "yes" for an identity it does not know yet,
    // so the lock resolves a frame late. Until it does the controls stay off:
    // lighting them up invites a tap that can only end in a 403, and the lock
    // banner then lands on top of it.
    final repo = _FakeSettingsRepo(modernSettings());
    final verdict = Completer<void>();
    repo.verdict = verdict;
    usePhoneWindow(tester, dp: 1800);
    addTearDown(tester.view.reset);

    await pumpPhone(
      tester,
      const QueueSettingsScreen(),
      overrides: [
        fakeServerProfileOverride(authMode: AuthMode.jwt),
        currentUserOverride(
          const CurrentUser(id: 1, username: 'ola', isAdmin: true),
        ),
        serverSettingsRepositoryProvider.overrideWithValue(repo),
      ],
    );
    // The settings are in; the verdict is still out.
    await tester.pumpAndSettle();

    for (final s in tester.widgetList<Switch>(find.byType(Switch))) {
      expect(s.onChanged, isNull, reason: 'unresolved is not writable');
    }
    expect(
      find.text(l10n.queueSettingsReadOnlyPermission),
      findsNothing,
      reason: 'and no banner flashes up for a session that turns out allowed',
    );

    verdict.complete();
    await tester.pumpAndSettle();
    expect(
      tester.widgetList<Switch>(find.byType(Switch)).first.onChanged,
      isNotNull,
      reason: 'the admin can write once the verdict lands',
    );
  });

  group('after a write', () {
    testWidgets('the reply is taken as the answer, with no second read', (
      tester,
    ) async {
      final repo = await pumpScreen(tester, modernSettings(keepWarm: false));
      final readsAfterLoad = repo.reads;

      await tester.tap(find.text(l10n.queueSettingsKeepWarmTitle));
      await tester.pumpAndSettle();

      expect(repo.writes, hasLength(1));
      expect(
        repo.reads,
        readsAfterLoad,
        reason:
            'PUT answers with the whole of AppSettings; asking again is a '
            'request that can only agree, or fail',
      );
      expect(switchFor(tester, l10n.queueSettingsKeepWarmTitle).value, isTrue);
    });

    testWidgets('a read that fails afterwards cannot blank the screen', (
      tester,
    ) async {
      final repo = await pumpScreen(tester, modernSettings(keepWarm: false));

      await tester.tap(find.text(l10n.queueSettingsKeepWarmTitle));
      await tester.pumpAndSettle();

      // Whatever else asks for the settings next, a dropped answer must not
      // take the rows away under a save that worked.
      repo.readFails = true;
      await containerOf(tester).read(serverSettingsProvider.notifier).refresh();
      await tester.pumpAndSettle();

      expect(find.text(l10n.queueSettingsUnavailable), findsNothing);
      expect(switchFor(tester, l10n.queueSettingsKeepWarmTitle).value, isTrue);
    });
  });

  testWidgets('pull-to-refresh re-asks whether this session may write', (
    tester,
  ) async {
    // A 403 latches the form shut. The controls that would prove the
    // permission came back are the ones being greyed, so without the refresh
    // re-reading the verdict there is no way out short of restarting the app.
    final repo = await pumpScreen(
      tester,
      modernSettings(keepWarm: false),
      authMode: AuthMode.jwt,
      user: const CurrentUser(id: 1, username: 'ola', isAdmin: true),
      failWith: const AuthException(AppErrorCode.forbidden),
      // Short enough that the list really overscrolls, which is what the
      // refresh gesture needs.
      viewHeight: 1500,
    );

    // The top row, because the short window this test needs to overscroll at
    // all does not build the ones further down.
    await tester.tap(find.text(l10n.queueSettingsPlateClearTitle));
    await tester.pumpAndSettle();
    expect(find.text(l10n.queueSettingsReadOnlyPermission), findsOneWidget);

    repo.allowAgain();
    await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();

    expect(find.text(l10n.queueSettingsReadOnlyPermission), findsNothing);
    expect(
      switchFor(tester, l10n.queueSettingsPlateClearTitle).onChanged,
      isNotNull,
      reason: 'the form reopens without restarting the app',
    );
  });

  group('who may write', () {
    testWidgets('an API-key session reads the values and cannot change them', (
      tester,
    ) async {
      final repo = await pumpScreen(
        tester,
        modernSettings(),
        authMode: AuthMode.apiKey,
      );

      expect(find.text(l10n.queueSettingsReadOnlyApiKey), findsOneWidget);
      expect(
        find.text(l10n.queueSettingsKeepWarmTitle),
        findsOneWidget,
        reason: 'the value stays readable — the verdict is on the write',
      );
      for (final s in tester.widgetList<Switch>(find.byType(Switch))) {
        expect(s.onChanged, isNull);
      }

      await tester.tap(find.text(l10n.queueSettingsKeepWarmTitle));
      await tester.pumpAndSettle();
      expect(repo.writes, isEmpty);
    });

    testWidgets('an account without settings:update is told which one it is', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        modernSettings(),
        authMode: AuthMode.jwt,
        user: const CurrentUser(
          id: 1,
          username: 'ola',
          isAdmin: false,
          permissions: {'queue:read'},
          permissionsKnown: true,
        ),
      );

      expect(find.text(l10n.queueSettingsReadOnlyPermission), findsOneWidget);
      expect(find.text(l10n.queueSettingsReadOnlyApiKey), findsNothing);
    });

    testWidgets('a server with authentication off is writable, not locked', (
      tester,
    ) async {
      // The case the administration gate gets wrong: nobody is signed in, and
      // `RequirePermissionIfAuthEnabled` has nobody to refuse.
      final repo = await pumpScreen(tester, modernSettings());

      expect(find.text(l10n.queueSettingsReadOnlyApiKey), findsNothing);
      expect(find.text(l10n.queueSettingsReadOnlyPermission), findsNothing);

      await tester.tap(find.text(l10n.queueSettingsPlateClearTitle));
      await tester.pumpAndSettle();
      expect(repo.writes, [
        {'require_plate_clear': true},
      ]);
    });
  });
}

/// The settings route with nothing behind it. Extends the real repository so
/// the screen's own provider wiring is what is under test.
class _FakeSettingsRepo extends ServerSettingsRepository {
  _FakeSettingsRepo(this._settings, {this.failWith}) : super(Dio());

  Map<String, dynamic> _settings;
  AppApiException? failWith;
  bool _refused = false;

  /// A write naming one of these keys waits for its completer. Held per key,
  /// not one for all of them: the point of the test below is a write that is
  /// still in flight while another one has already failed.
  final Map<String, Completer<void>> gates = {};

  /// A write naming this key is refused; every other one succeeds. Lets a test
  /// fail exactly one of two writes that are in flight together.
  String? failKey;

  /// Holds the write verdict pending. In the app the wait is real — the lock
  /// reads `/auth/me` — and the fake resolves instantly without this.
  Completer<void>? verdict;

  /// How many times the settings were read. A save must not cause one.
  int reads = 0;

  /// The next read answers with nothing, as a failed one does.
  bool readFails = false;

  /// The bodies `PUT /settings/` was given, in order.
  final List<Map<String, dynamic>> writes = [];

  @override
  Future<Map<String, dynamic>> fetch() async {
    reads++;
    return readFails ? const {} : _settings;
  }

  @override
  Future<Map<String, dynamic>> update(Map<String, dynamic> changes) async {
    writes.add(changes);
    for (final key in changes.keys) {
      final gate = gates[key];
      if (gate != null) await gate.future;
    }
    final failure = changes.containsKey(failKey)
        ? const ApiException(AppErrorCode.badResponse, statusCode: 500)
        : failWith;
    if (failure == null) return _settings = {..._settings, ...changes};
    _refused |= failure.code == AppErrorCode.forbidden;
    throw failure;
  }

  @override
  Future<bool> writable() async {
    await verdict?.future;
    return !_refused;
  }

  /// The permission an administrator just granted back.
  void allowAgain() {
    _refused = false;
    failWith = null;
  }
}
