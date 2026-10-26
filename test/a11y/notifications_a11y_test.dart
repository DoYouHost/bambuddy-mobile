import 'package:bambuddy_mobile/core/notifications/notification_service.dart';
import 'package:bambuddy_mobile/features/notifications/notification_settings_screen.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers.dart';
import 'a11y_harness.dart';

/// Rendered contrast and touch targets for the notification settings: the
/// default screen, the master switch off (every event row and threshold slider
/// greyed) and the "system is swallowing alerts" banner. Not covered: the alerts
/// and the ongoing notification themselves, which are system UI rather than a
/// screen of this app.
void main() {
  a11ySurface(
    'notification settings',
    demo: false,
    overrides: [noServerProfileOverride, _quiet],
    home: () => const NotificationSettingsScreen(),
    shows: find.text(pl.notifMasterTitle),
  );

  a11ySurface(
    'notification settings, master off',
    demo: false,
    overrides: [noServerProfileOverride, _quiet],
    home: () => const NotificationSettingsScreen(),
    arrange: (tester) async {
      // The master row and the event rows share one id; the master is first.
      await tester.tap(byLogId('notification_settings.event').first);
      await settle(tester);
      // Proves the switch took: the first event row is now disabled.
      expect(
        tester.widget<Switch>(find.byType(Switch).at(1)).onChanged,
        isNull,
      );
    },
    shows: find.text(pl.notifMasterTitle),
  );

  a11ySurface(
    'notification settings, blocked by the system',
    demo: false,
    overrides: [
      noServerProfileOverride,
      notificationServiceProvider.overrideWithValue(_Muted()),
    ],
    home: () => const NotificationSettingsScreen(),
    shows: find.text(pl.notificationsBlocked),
  );
}

final _quiet = notificationServiceProvider.overrideWithValue(
  RecordingNotifications(),
);

/// A real [LocalNotificationService] whose permission query says "refused": the
/// screen only draws its banner for that type, and the plugin behind it has no
/// platform to ask in a test.
class _Muted extends LocalNotificationService {
  @override
  Future<bool?> notificationsEnabled() async => false;
}
