import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/auth/auth_service.dart';
import '../../core/settings/server_profile.dart';
import '../../providers.dart';

/// Błędy walidacji/konfiguracji pochodzące z samego ekranu setupu
/// (w odróżnieniu od [AppApiException] z warstwy sieci). Tłumaczone w UI.
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

  /// [SetupErrorCode] albo [AppApiException]; tłumaczone przy wyświetlaniu.
  final Object? error;

  /// Wynik sondy trybu auth; null = URL jeszcze nie zweryfikowany.
  final AuthProbeResult? probe;

  /// Znormalizowany URL, ustalony przy udanej sondzie.
  final String? baseUrl;

  /// Sonda przeszła i serwer wymaga uwierzytelnienia.
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

  /// Sonduje tryb auth serwera. Gdy auth wyłączony — od razu zapisuje
  /// profil (zero dodatkowych kroków dla najprostszej konfiguracji).
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
      if (!probe.authEnabled) {
        await _saveProfile(url, AuthMode.none);
        return;
      }
      state = SetupState(probe: probe, baseUrl: url);
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

  /// Zapis profilu przełącza router na dashboard (patrz routerProvider).
  Future<void> _saveProfile(String url, AuthMode mode) =>
      ref.read(serverProfileProvider.notifier).save(
            ServerProfile(baseUrl: url, authMode: mode),
          );
}
