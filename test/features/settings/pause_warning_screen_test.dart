import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/format/duration_format.dart';
import 'package:bambuddy_mobile/core/models/current_user.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/core/theme/dash_theme.dart';
import 'package:bambuddy_mobile/data/server_settings_repository.dart';
import 'package:bambuddy_mobile/features/settings/pause_warning_screen.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers.dart';

/// `pause_warning_minutes` (server #2984): the server's own lead time, which the
/// app warns by too. Who may move it is the queue settings' answer; for everyone
/// else the screen is a read-out of what the server holds.
class _Repo extends ServerSettingsRepository {
  _Repo(this._settings, {this.failWith}) : super(Dio());

  Map<String, dynamic> _settings;
  final AppApiException? failWith;
  final List<Map<String, dynamic>> writes = [];

  @override
  Future<Map<String, dynamic>> fetch() async => _settings;

  @override
  Future<Map<String, dynamic>> update(Map<String, dynamic> changes) async {
    writes.add(changes);
    final failure = failWith;
    if (failure == null) return _settings = {..._settings, ...changes};
    if (failure.code == AppErrorCode.forbidden) {
      writableCapability.observeRefusal();
    }
    throw failure;
  }
}

void main() {
  Future<_Repo> pump(
    WidgetTester tester,
    Map<String, dynamic> settings, {
    AuthMode authMode = AuthMode.none,
    CurrentUser? user,
    AppApiException? failWith,
    double textScale = 1,
  }) async {
    usePhoneWindow(tester, dp: 1000);
    final repo = _Repo(settings, failWith: failWith);
    await pumpPhone(
      tester,
      const PauseWarningScreen(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      overrides: [
        fakeServerProfileOverride(authMode: authMode),
        currentUserOverride(user),
        serverSettingsRepositoryProvider.overrideWithValue(repo),
      ],
    );
    await tester.pumpAndSettle();
    return repo;
  }

  SettingsSlider slider(WidgetTester tester) =>
      tester.widget<SettingsSlider>(find.byType(SettingsSlider));

  const held = {'pause_warning_minutes': 10};

  testWidgets('shows the server\'s value and says what it changes', (
    tester,
  ) async {
    await pump(tester, held);

    expect(
      find.text(pl.pauseWarningLabel(formatMinutes(pl, 10))),
      findsOneWidget,
    );
    expect(find.text(pl.pauseWarningDesc), findsOneWidget);
    expect(slider(tester).value, 10);
    expect(slider(tester).min, 1);
    expect(slider(tester).max, 120);
  });

  testWidgets('a server that does not send the key offers nothing to write', (
    tester,
  ) async {
    await pump(tester, const {'use_slicer_api': true});

    expect(find.byType(SettingsSlider), findsNothing);
    expect(find.text(pl.queueSettingsUnavailable), findsOneWidget);
  });

  group('who may change it', () {
    testWidgets('a server with authentication off', (tester) async {
      await pump(tester, held);
      expect(slider(tester).enabled, isTrue);
    });

    testWidgets('an account with settings:update', (tester) async {
      await pump(
        tester,
        held,
        authMode: AuthMode.jwt,
        user: const CurrentUser(id: 1, username: 'ola', isAdmin: true),
      );
      expect(slider(tester).enabled, isTrue);
      expect(find.text(pl.queueSettingsReadOnlyPermission), findsNothing);
    });

    testWidgets('an account without it sees the value and why it is fixed', (
      tester,
    ) async {
      await pump(
        tester,
        held,
        authMode: AuthMode.jwt,
        user: const CurrentUser(
          id: 2,
          username: 'ola',
          isAdmin: false,
          permissions: {'queue:read'},
          permissionsKnown: true,
        ),
      );

      expect(slider(tester).enabled, isFalse);
      expect(slider(tester).value, 10);
      expect(find.text(pl.queueSettingsReadOnlyPermission), findsOneWidget);
    });

    testWidgets('an API key sees the value and why it is fixed', (
      tester,
    ) async {
      final repo = await pump(tester, held, authMode: AuthMode.apiKey);

      expect(slider(tester).enabled, isFalse);
      expect(slider(tester).value, 10);
      expect(find.text(pl.queueSettingsReadOnlyApiKey), findsOneWidget);

      // A drag on a disabled slider is not a write.
      await tester.drag(find.byType(Slider), const Offset(60, 0));
      await tester.pumpAndSettle();
      expect(repo.writes, isEmpty);
    });
  });

  group('writing it', () {
    testWidgets('writes once, on release, only this key', (tester) async {
      final repo = await pump(tester, held);

      final finger = await tester.startGesture(
        tester.getCenter(find.byType(Slider)),
      );
      await finger.moveBy(const Offset(60, 0));
      await tester.pump();
      expect(repo.writes, isEmpty, reason: 'still dragging');

      await finger.up();
      await tester.pumpAndSettle();

      expect(repo.writes, hasLength(1));
      expect(repo.writes.single.keys, ['pause_warning_minutes']);
      expect(
        repo.writes.single['pause_warning_minutes'],
        inInclusiveRange(1, 120),
      );
      expect(slider(tester).value, repo.writes.single['pause_warning_minutes']);
    });

    testWidgets('a refusal puts the server\'s value back and says why', (
      tester,
    ) async {
      final repo = await pump(
        tester,
        held,
        authMode: AuthMode.jwt,
        user: const CurrentUser(id: 1, username: 'ola', isAdmin: true),
        failWith: const AuthException(
          AppErrorCode.forbidden,
          detail: 'Missing required permissions: settings:update',
        ),
      );

      final finger = await tester.startGesture(
        tester.getCenter(find.byType(Slider)),
      );
      await finger.moveBy(const Offset(60, 0));
      await finger.up();
      await tester.pumpAndSettle();

      expect(repo.writes, hasLength(1));
      expect(slider(tester).value, 10, reason: 'back to what the server has');
      expect(
        find.textContaining('Missing required permissions'),
        findsOneWidget,
      );
      expect(slider(tester).enabled, isFalse, reason: 'and now fixed');
    });
  });

  for (final scale in const [1.0, 1.5, 2.0]) {
    testWidgets('fits at text scale $scale', (tester) async {
      await pump(tester, held, authMode: AuthMode.apiKey, textScale: scale);

      expect(tester.takeException(), isNull);
      expect(find.text(pl.queueSettingsReadOnlyApiKey), findsOneWidget);
    });
  }
}
