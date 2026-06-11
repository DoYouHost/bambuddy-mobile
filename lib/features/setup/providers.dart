import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/auth/auth_service.dart';
import '../../core/settings/server_profile.dart';
import '../../providers.dart';

class SetupState {
  const SetupState({
    this.busy = false,
    this.error,
    this.probe,
    this.baseUrl,
  });

  final bool busy;
  final String? error;

  /// Wynik sondy trybu auth; null = URL jeszcze nie zweryfikowany.
  final AuthProbeResult? probe;

  /// Znormalizowany URL, ustalony przy udanej sondzie.
  final String? baseUrl;

  /// Sonda przeszła i serwer wymaga uwierzytelnienia.
  bool get needsAuth => probe?.authEnabled == true;

  SetupState copyWith({
    bool? busy,
    String? error,
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
      state = state.copyWith(error: 'Podaj adres serwera');
      return;
    }
    state = const SetupState(busy: true);
    try {
      final probe =
          await ref.read(authServiceProvider).probeAuthStatus(url);
      if (probe.requiresSetup) {
        state = SetupState(
          error: 'Serwer wymaga początkowej konfiguracji — '
              'dokończ ją w przeglądarce i wróć tutaj.',
        );
        return;
      }
      if (!probe.authEnabled) {
        await _saveProfile(url, AuthMode.none);
        return;
      }
      state = SetupState(probe: probe, baseUrl: url);
    } on AppApiException catch (e) {
      state = SetupState(error: e.message);
    }
  }

  Future<void> connectWithApiKey(String apiKey) async {
    final url = state.baseUrl;
    if (url == null) return;
    if (apiKey.trim().isEmpty) {
      state = state.copyWith(error: 'Podaj klucz API');
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
      state = state.copyWith(busy: false, error: e.message);
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
      state = state.copyWith(error: 'Podaj login i hasło');
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
      state = state.copyWith(busy: false, error: e.message);
    }
  }

  /// Zapis profilu przełącza router na dashboard (patrz routerProvider).
  Future<void> _saveProfile(String url, AuthMode mode) =>
      ref.read(serverProfileProvider.notifier).save(
            ServerProfile(baseUrl: url, authMode: mode),
          );
}
