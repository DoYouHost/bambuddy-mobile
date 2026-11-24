import 'package:bambuddy_mobile/core/notifications/finish_alert_memory.dart';
import 'package:bambuddy_mobile/core/notifications/notification_prefs.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/core/settings/settings_repository.dart';
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the app remembers by row id belongs to the server that issued the id:
/// maintenance items already announced, the last print-ended alert per
/// printer, and the printer whose maintenance log was open last.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SettingsRepository settings;
  late FinishAlertMemory finished;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settings = SettingsRepository(prefs);
    finished = FinishAlertMemory(prefs);
    await settings.saveProfile(_profile(_serverA));
    await settings.saveNotifiedMaintenanceDueIds({10, 12}, serverUrl: _serverA);
    await settings.saveMaintenanceLogPrinter(3);
    await finished.remember(
      PostedAlert(
        event: NotifEvent.printFinished,
        printerId: 1,
        id: 1000001,
        title: 'done',
        body: 'job',
        postedAt: clock.now(),
      ),
    );
  });

  test('another server starts with nothing remembered', () async {
    await settings.saveProfile(_profile(_serverB));

    expect(settings.loadNotifiedMaintenanceDueIds(), isEmpty);
    expect(await finished.entries(), isEmpty);
    expect(settings.loadMaintenanceLogPrinter(), isNull);
  });

  test('signing out forgets it too', () async {
    await settings.clearProfile();
    await settings.saveProfile(_profile(_serverA));

    expect(settings.loadNotifiedMaintenanceDueIds(), isEmpty);
    expect(await finished.entries(), isEmpty);
  });

  // A session that lapsed is signed back into without a sign-out; announcing
  // every overdue item again would be the price of forgetting here.
  test('the same server saved again keeps what it knew', () async {
    await settings.saveProfile(
      const ServerProfile(baseUrl: _serverA, authMode: AuthMode.apiKey),
    );

    expect(settings.loadNotifiedMaintenanceDueIds(), {10, 12});
    expect(await finished.entries(), hasLength(1));
    expect(settings.loadMaintenanceLogPrinter(), 3);
  });
}

ServerProfile _profile(String url) =>
    ServerProfile(baseUrl: url, authMode: AuthMode.jwt);

const _serverA = 'http://192.168.1.10:8000';
const _serverB = 'http://192.168.1.20:8000';
