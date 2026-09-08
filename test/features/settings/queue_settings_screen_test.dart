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
  }) async {
    // The default 800x600 window builds only the first section of the list,
    // and every gate this file is about sits further down it. A phone-shaped
    // window puts the whole screen on one page.
    tester.view.physicalSize = const Size(1080, 5400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

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
      // Empty, but rendered — not an error view.
      expect(find.text(l10n.queueSettingsTitle), findsOneWidget);
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
      // The keep-warm section is there, minus the row the server lacks: the
      // bed temperature has a slider, the hold duration has none.
      expect(find.text(l10n.queueSettingsKeepWarmTitle), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
    });
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
  final AppApiException? failWith;
  bool _refused = false;

  /// The bodies `PUT /settings/` was given, in order.
  final List<Map<String, dynamic>> writes = [];

  @override
  Future<Map<String, dynamic>> fetch() async => _settings;

  @override
  Future<Map<String, dynamic>> update(Map<String, dynamic> changes) async {
    writes.add(changes);
    final failure = failWith;
    if (failure == null) return _settings = {..._settings, ...changes};
    _refused |= failure.code == AppErrorCode.forbidden;
    throw failure;
  }

  @override
  Future<bool> writable() async => !_refused;
}
