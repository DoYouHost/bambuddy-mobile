import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/auth/credentials_store.dart';
import '../../core/demo/demo_backend.dart';
import '../../core/app_context.dart';
import '../../core/notifications/background_monitor.dart';
import '../../core/notifications/background_sync.dart';
import '../../core/notifications/notification_prefs.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/settings/server_profile.dart';
import '../../providers.dart';
import 'tour_beacon.dart';

/// The tour's own world: the demo server in a container with no parent.
///
/// No parent on purpose — a nested `ProviderScope` resolves every provider it
/// does not override in the app's container, where it would read the user's
/// real profile. Everything that could leave the process (preferences, secure
/// storage, notifications, the background service) is swapped for a stand-in
/// that forgets with the container. The home widget (`_publishWidget`) and
/// the watch relay (the dashboard's lifecycle, its only reader on these
/// screens) are skipped through [tourBeaconProvider].
///
/// The demo backend is process-wide, so the tour swaps in a fresh one and
/// [TourSandbox.dispose] puts the previous one back — edits made during the tour
/// never reach a demo the user may be signed into.
class TourSandbox {
  TourSandbox({required void Function(String event) onEvent})
    : beacon = TourBeacon(onEvent),
      _previousDemo = DemoBackend.instance,
      _previousPrintingCount = DemoBackend.printingPrinters {
    DemoBackend.instance = DemoBackend.fresh();
    // Every step is written against one printing machine.
    DemoBackend.printingPrinters = 1;
    container = ProviderContainer(
      retry: neverRetry,
      overrides: [
        tourBeaconProvider.overrideWithValue(beacon),
        serverProfileProvider.overrideWith(_DemoProfile.new),
        sharedPreferencesProvider.overrideWithValue(MemoryPreferences()),
        credentialsStoreProvider.overrideWithValue(InMemoryCredentialsStore()),
        notificationServiceProvider.overrideWithValue(_SilentNotifications()),
        backgroundMonitorProvider.overrideWithValue(_IdleMonitor()),
      ],
    );
  }

  final TourBeacon beacon;
  late final ProviderContainer container;
  final DemoBackend _previousDemo;
  final int _previousPrintingCount;

  void dispose() {
    container.dispose();
    DemoBackend.instance = _previousDemo;
    DemoBackend.printingPrinters = _previousPrintingCount;
  }
}

class _DemoProfile extends ServerProfileNotifier {
  @override
  ServerProfile? build() => const ServerProfile(
    baseUrl: DemoConfig.baseUrl,
    authMode: AuthMode.none,
    label: 'Demo',
  );
}

/// [SharedPreferences] held in a map, so nothing the tour sets reaches the
/// phone's store. Starts empty: every screen opens in its default layout.
class MemoryPreferences implements SharedPreferences {
  final _values = <String, Object>{};

  Future<bool> _set(String key, Object value) async {
    _values[key] = value;
    return true;
  }

  @override
  Set<String> getKeys() => Set.of(_values.keys);

  @override
  Object? get(String key) => _values[key];

  @override
  bool? getBool(String key) => _values[key] as bool?;

  @override
  int? getInt(String key) => _values[key] as int?;

  @override
  double? getDouble(String key) => _values[key] as double?;

  @override
  String? getString(String key) => _values[key] as String?;

  @override
  List<String>? getStringList(String key) =>
      (_values[key] as List<String>?)?.toList();

  @override
  bool containsKey(String key) => _values.containsKey(key);

  @override
  Future<bool> setBool(String key, bool value) => _set(key, value);

  @override
  Future<bool> setInt(String key, int value) => _set(key, value);

  @override
  Future<bool> setDouble(String key, double value) => _set(key, value);

  @override
  Future<bool> setString(String key, String value) => _set(key, value);

  @override
  Future<bool> setStringList(String key, List<String> value) =>
      _set(key, value.toList());

  @override
  Future<bool> remove(String key) async {
    _values.remove(key);
    return true;
  }

  @override
  Future<bool> clear() async {
    _values.clear();
    return true;
  }

  @override
  Future<bool> commit() async => true;

  /// A real instance re-reads the phone's store here.
  @override
  Future<void> reload() async {}
}

class _SilentNotifications implements NotificationService {
  @override
  Future<void> init() async {}

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> showOngoing({
    required String title,
    required String body,
    required int? progress,
  }) async {}

  @override
  Future<void> clearOngoing() async {}

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
  }) async {}

  @override
  Future<bool> isAlertActive(int id) async => false;
}

class _IdleMonitor implements BackgroundMonitor {
  @override
  Future<bool> start() async => false;

  @override
  Future<bool> stop() async => false;

  @override
  Future<bool> isRunning() async => false;

  @override
  void sync(BackgroundSync what) {}
}
