import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/auth/auth_service.dart';
import '../../core/auth/two_factor.dart';
import '../../core/demo/demo_config.dart';
import '../../core/diagnostics/auth_probe.dart';
import '../../core/models/current_user.dart';
import '../../core/settings/server_profile.dart';
import '../../providers.dart';

/// Validation/configuration errors from setup screen itself (distinct from
/// [AppApiException] from network layer). Translated in UI.
enum SetupErrorCode {
  missingUrl,
  missingApiKey,
  missingCredentials,
  missingTwoFactorCode,
  requiresServerSetup,
}

class SetupState {
  const SetupState({
    this.busy = false,
    this.error,
    this.probe,
    this.baseUrl,
    this.twoFactor,
    this.emailCodeSent = false,
  });

  final bool busy;

  /// [SetupErrorCode] or [AppApiException]; translated on display.
  final Object? error;

  /// Auth mode probe result; null = URL not yet verified.
  final AuthProbeResult? probe;

  /// Normalized URL, set on successful probe.
  final String? baseUrl;

  /// Set when the password went through but the account wants a second factor.
  /// Non-null = the screen shows the code step instead of the login form.
  final TwoFactorChallenge? twoFactor;

  /// A code has been mailed for the current challenge — turns the send button
  /// into a resend and tells the user where to look.
  final bool emailCodeSent;

  /// Probe passed and server requires authentication.
  bool get needsAuth => probe?.authEnabled == true;

  SetupState copyWith({
    bool? busy,
    Object? error,
    AuthProbeResult? probe,
    String? baseUrl,
    TwoFactorChallenge? twoFactor,
    bool? emailCodeSent,
    bool clearTwoFactor = false,
  }) =>
      SetupState(
        busy: busy ?? this.busy,
        error: error,
        probe: probe ?? this.probe,
        baseUrl: baseUrl ?? this.baseUrl,
        twoFactor: clearTwoFactor ? null : twoFactor ?? this.twoFactor,
        emailCodeSent: clearTwoFactor ? false : emailCodeSent ?? this.emailCodeSent,
      );
}

final setupControllerProvider =
    AutoDisposeNotifierProvider<SetupController, SetupState>(
  SetupController.new,
);

/// How long the controller leaves the code step up before declaring the
/// challenge stale. Overridden in tests to keep them off the clock.
final twoFactorLifetimeProvider =
    Provider<Duration>((ref) => TwoFactorChallenge.lifetime);

class SetupController extends AutoDisposeNotifier<SetupState> {
  /// Counts down the pre-auth token so an untouched code step gives way to the
  /// password form on its own, instead of waiting for the user to type a
  /// perfectly good code into a challenge the server forgot minutes ago.
  Timer? _twoFactorExpiry;

  @override
  SetupState build() {
    ref.onDispose(() => _twoFactorExpiry?.cancel());
    return const SetupState();
  }

  /// (Re)starts the countdown — a fresh challenge, and every token the e-mail
  /// step swaps in, gets the full window.
  void _armTwoFactorExpiry() {
    _twoFactorExpiry?.cancel();
    _twoFactorExpiry = Timer(ref.read(twoFactorLifetimeProvider), () {
      if (state.twoFactor == null) return;
      AuthProbe.twoFactorLapsed();
      state = state.copyWith(
        clearTwoFactor: true,
        error: const AuthException(AppErrorCode.twoFactorChallengeExpired),
      );
    });
  }

  void _cancelTwoFactorExpiry() {
    _twoFactorExpiry?.cancel();
    _twoFactorExpiry = null;
  }

  /// Probe server auth mode. If auth disabled — immediately save profile
  /// (zero extra steps for simplest setup).
  Future<void> probe(String rawUrl) async {
    final url = ServerProfile.normalizeBaseUrl(rawUrl);
    if (url.isEmpty) {
      state = state.copyWith(error: SetupErrorCode.missingUrl);
      return;
    }
    // Demo mode (store review): recognized locally, no network probe.
    // Present the login form; credentials are validated in connectWith*.
    if (DemoConfig.isDemoUrl(url)) {
      state = SetupState(
        probe: (
          authEnabled: true,
          requiresSetup: false,
          baseUrl: DemoConfig.baseUrl,
        ),
        baseUrl: DemoConfig.baseUrl,
      );
      return;
    }
    state = const SetupState(busy: true);
    try {
      final probe =
          await ref.read(authServiceProvider).probeAuthStatus(url);
      // Only a server that has neither finished setup NOR got auth turned on is
      // genuinely unusable — that's also the sole case the web UI redirects to
      // /setup for. `requires_setup` alone stays true forever on installs whose
      // `setup_completed` row is missing (DB restored, pre-dates the key), and
      // there the wizard can't clear it: POST /auth/setup answers 403 once auth
      // is enabled. Blocking on it locked out working servers.
      if (probe.requiresSetup && !probe.authEnabled) {
        state = const SetupState(error: SetupErrorCode.requiresServerSetup);
        return;
      }
      // Adopt the URL actually reached (probe followed any http→https redirect),
      // so REST and WS share the same scheme — otherwise ws:// fails silently.
      final effectiveUrl = probe.baseUrl;
      if (!probe.authEnabled) {
        await _saveProfile(effectiveUrl, AuthMode.none);
        return;
      }
      state = SetupState(probe: probe, baseUrl: effectiveUrl);
    } on AppApiException catch (e) {
      state = SetupState(error: e);
    }
  }

  Future<void> connectWithApiKey(String apiKey) async {
    final url = state.baseUrl;
    if (url == null) return;
    if (apiKey.trim().isEmpty) {
      state = state.copyWith(error: SetupErrorCode.missingApiKey);
      return;
    }
    state = state.copyWith(busy: true, error: null);
    if (url == DemoConfig.baseUrl) {
      // Demo accepts its password as an "API key" too, so the reviewer
      // succeeds regardless of which auth tab they pick.
      if (apiKey.trim() == DemoConfig.password) {
        await _saveDemoProfile();
      } else {
        state = state.copyWith(
          busy: false,
          error: const AuthException(AppErrorCode.apiKeyRejected),
        );
      }
      return;
    }
    try {
      await ref.read(authServiceProvider).verifyAndStoreApiKey(
            baseUrl: url,
            apiKey: apiKey.trim(),
          );
      await _saveProfile(url, AuthMode.apiKey);
    } on AppApiException catch (e) {
      state = state.copyWith(busy: false, error: e);
    }
  }

  Future<void> connectWithLogin({
    required String username,
    required String password,
    required bool remember,
  }) async {
    final url = state.baseUrl;
    if (url == null) return;
    if (username.isEmpty || password.isEmpty) {
      state = state.copyWith(error: SetupErrorCode.missingCredentials);
      return;
    }
    state = state.copyWith(busy: true, error: null);
    if (url == DemoConfig.baseUrl) {
      if (username == DemoConfig.username && password == DemoConfig.password) {
        await _saveDemoProfile();
      } else {
        state = state.copyWith(
          busy: false,
          error: const AuthException(AppErrorCode.invalidCredentials),
        );
      }
      return;
    }
    try {
      final result = await ref.read(authServiceProvider).login(
            baseUrl: url,
            username: username,
            password: password,
            remember: remember,
          );
      switch (result) {
        case LoginCompleted(:final user):
          _adopt(user);
          await _saveProfile(url, AuthMode.jwt);
        case LoginNeedsTwoFactor(:final challenge):
          state = state.copyWith(busy: false, twoFactor: challenge);
          _armTwoFactorExpiry();
          // An account whose only factor is e-mail has nothing to type until a
          // code has been mailed, so asking the user to press "send" first is a
          // step that can only go one way. With more than one method the choice
          // is theirs — mailing a code they weren't going to use would be spam
          // against a 3-per-15-minutes server limit.
          if (challenge.methods.singleOrNull == TwoFactorMethod.email) {
            await sendTwoFactorEmailCode();
          }
      }
    } on AppApiException catch (e) {
      state = state.copyWith(busy: false, error: e);
    }
  }

  /// Mails a fresh e-mail OTP for the pending challenge. Replaces the stored
  /// challenge: the server hands back a new pre-auth token and voids the old.
  Future<void> sendTwoFactorEmailCode() async {
    final url = state.baseUrl;
    final challenge = state.twoFactor;
    if (url == null || challenge == null) return;
    state = state.copyWith(busy: true, error: null);
    try {
      final refreshed = await ref.read(authServiceProvider).sendEmailOtp(
            baseUrl: url,
            challenge: challenge,
          );
      state = state.copyWith(
        busy: false,
        twoFactor: refreshed,
        emailCodeSent: true,
      );
      // The server issued a new token with it, so the clock starts over.
      _armTwoFactorExpiry();
    } on AppApiException catch (e) {
      state = state.copyWith(busy: false, error: e);
    }
  }

  /// Second step: exchange the code for a session. A rejected code leaves the
  /// challenge in place (the server does not spend it), so the user just types
  /// the next one; an expired challenge drops back to the password form,
  /// because only a fresh login can mint another.
  Future<void> verifyTwoFactor({
    required TwoFactorMethod method,
    required String code,
  }) async {
    final url = state.baseUrl;
    final challenge = state.twoFactor;
    if (url == null || challenge == null) return;
    if (code.trim().isEmpty) {
      state = state.copyWith(error: SetupErrorCode.missingTwoFactorCode);
      return;
    }
    state = state.copyWith(busy: true, error: null);
    try {
      final completed = await ref.read(authServiceProvider).verifyTwoFactor(
            baseUrl: url,
            challenge: challenge,
            method: method,
            code: code,
          );
      _adopt(completed.user);
      _cancelTwoFactorExpiry();
      await _saveProfile(url, AuthMode.jwt);
    } on AppApiException catch (e) {
      final expired = e.code == AppErrorCode.twoFactorChallengeExpired;
      if (expired) _cancelTwoFactorExpiry();
      state = state.copyWith(busy: false, error: e, clearTwoFactor: expired);
    }
  }

  /// Back to the password form — "wrong account", or the authenticator is on
  /// the other phone.
  void cancelTwoFactor() {
    _cancelTwoFactorExpiry();
    state = state.copyWith(error: null, clearTwoFactor: true);
  }

  /// Hands the identity the login answer already carried to
  /// [currentUserProvider], before the profile save rebuilds it — that way a
  /// sign-in needs no `GET /auth/me` of its own. A server that sent no `user`
  /// leaves it to fetch one.
  void _adopt(CurrentUser? user) {
    if (user == null) return;
    ref.read(currentUserProvider.notifier).adopt(user);
  }

  /// Profile save switches router to dashboard (see routerProvider).
  Future<void> _saveProfile(String url, AuthMode mode) =>
      ref.read(serverProfileProvider.notifier).save(
            ServerProfile(baseUrl: url, authMode: mode),
          );

  /// Demo profile uses [AuthMode.none]: the fake backend needs no credentials,
  /// and this keeps token refresh / silent re-login machinery fully off.
  Future<void> _saveDemoProfile() =>
      ref.read(serverProfileProvider.notifier).save(
            const ServerProfile(
              baseUrl: DemoConfig.baseUrl,
              authMode: AuthMode.none,
              label: 'Demo',
            ),
          );
}
