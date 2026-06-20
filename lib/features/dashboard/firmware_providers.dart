import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/models/firmware.dart';
import '../../providers.dart';

/// Firmware całej farmy zmapowane po `printerId` — źródło dla karty drukarki
/// (wersja + flaga „dostępna aktualizacja"). Firmware zmienia się rzadko i
/// sprawdzenie bije po chmurze, więc NIE pollujemy: pobieramy raz przy wejściu
/// i odświeżamy jawnie ([FirmwareNotifier.refresh], pull-to-refresh / po
/// przyszłym wykonaniu aktualizacji).
///
/// Błąd (chmura nieosiągalna itp.) zostaje w `AsyncError` — karta po prostu nie
/// pokazuje firmware (`valueOrNull == null`), nigdy nie wywraca dashboardu.
final firmwareProvider =
    AsyncNotifierProvider<FirmwareNotifier, Map<int, FirmwareUpdateInfo>>(
  FirmwareNotifier.new,
);

class FirmwareNotifier extends AsyncNotifier<Map<int, FirmwareUpdateInfo>> {
  @override
  Future<Map<int, FirmwareUpdateInfo>> build() {
    // Przebudowa przy zmianie profilu serwera (inny serwer → inne firmware).
    ref.watch(serverProfileProvider);
    return _load();
  }

  Future<Map<int, FirmwareUpdateInfo>> _load() async {
    final resp = await ref.read(firmwareRepositoryProvider).fetchUpdates();
    return {
      for (final u in resp.updates)
        if (u.printerId != null) u.printerId!: u,
    };
  }

  /// Ponowne sprawdzenie firmware (zachowuje poprzednie dane pod spodem, żeby
  /// UI nie mrugało). Auth wypływa jako [AuthException] — dashboard odeśle do /setup.
  Future<void> refresh() async {
    state = const AsyncValue<Map<int, FirmwareUpdateInfo>>.loading()
        .copyWithPrevious(state);
    state = await AsyncValue.guard(_load);
  }
}

/// Firmware pojedynczej drukarki (lub `null`, gdy brak danych/jeszcze ładuje).
/// Cienki selektor nad [firmwareProvider] — karta nie musi znać kształtu mapy.
final printerFirmwareProvider =
    Provider.family<FirmwareUpdateInfo?, int>((ref, printerId) {
  return ref.watch(firmwareProvider).valueOrNull?[printerId];
});

/// Czy w ogóle warto pokazywać błąd auth z firmware na zewnątrz. Trzymane tu,
/// by ewentualny przyszły UI flow miał gdzie sięgnąć (na razie nieużywane).
bool isFirmwareAuthError(Object? error) =>
    error is AuthException && error.code == AppErrorCode.unauthorized;
