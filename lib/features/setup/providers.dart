import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/auth/auth_service.dart';
import '../../core/settings/server_profile.dart';
import '../../providers.dart';

/// Validation/configuration errors from setup screen itself (distinct from
/// [AppApiException] from network layer). Translated in UI.
enum SetupErrorCode {
  missingUrl,
  missingApiKey,
  missingCredentials,
  requiresServerSetup,
}

class SetupState {
  const SetupState({
    this.busy = false,
    this.error,
    this.probe,
    this.baseUrl,
  });

  final bool busy;

  /// [SetupErrorCode] or [AppApiException]; translated on display.
  final Object? error;

  /// Auth mode probe result; null = URL not yet verified.
  final AuthProbeResult? probe;

  /// Normalized URL, set on successful probe.
  final String? baseUrl;

  /// Probe passed and server requires authentication.
  bool get needsAuth => probe?.authEnabled == true;

  SetupState copyWith({
    bool? busy,
    Object? error,
    AuthProbeResult? probe,
    String? baseUrl,
  }) =>
      SetupState(
        busy: busy ?? this.busy,
        error: error,
        probe: probe ?? this.probe,
        baseUrl: baseUrl ?? this.baseUrl,
      );
}

final setupControllerProvider =
    AutoDisposeNotifierProvider<SetupController, SetupState>(
  SetupController.new,
);

class SetupController extends AutoDisposeNotifier<SetupState> {
  @override
  SetupState build() => const SetupState();

  /// Probe server auth mode. If auth disabled — immediately save profile
  /// (zero extra steps for simplest setup).
  Future<void> probe(String rawUrl) async {
    final url = ServerProfile.normalizeBaseUrl(rawUrl);
    if (url.isEmpty) {
      state = state.copyWith(error: SetupErrorCode.missingUrl);
      return;
    }
    state = const SetupState(busy: true);
    try {
      final probe =
          await ref.read(authServiceProvider).probeAuthStatus(url);
      if (probe.requiresSetup) {
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
    try {
      await ref.read(authServiceProvider).login(
            baseUrl: url,
            username: username,
            password: password,
            remember: remember,
          );
      await _saveProfile(url, AuthMode.jwt);
    } on AppApiException catch (e) {
      state = state.copyWith(busy: false, error: e);
    }
  }

  /// Profile save switches router to dashboard (see routerProvider).
  Future<void> _saveProfile(String url, AuthMode mode) =>
      ref.read(serverProfileProvider.notifier).save(
            ServerProfile(baseUrl: url, authMode: mode),
          );
}
