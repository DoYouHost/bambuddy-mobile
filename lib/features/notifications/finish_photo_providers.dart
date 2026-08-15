import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notifications/finish_alert_memory.dart';
import '../../core/notifications/finish_photo_image.dart';
import '../../core/notifications/finish_photo_notifier.dart';
import '../../providers.dart';
import '../dashboard/ws_providers.dart';

/// The UI isolate's half of the finish-photo path.
///
/// The alert is always posted by the foreground service, but the photo arrives a
/// minute or so later — often after the user has opened the app, which stops
/// that service and leaves this isolate holding the only live socket. The two
/// never run at once (started on pause, stopped on resume), so a notification
/// cannot be updated twice; which one to update comes from [FinishAlertMemory],
/// since the isolate that posted it is gone by then.
final finishPhotoNotifierProvider = Provider<FinishPhotoNotifier?>((ref) {
  final profile = ref.watch(serverProfileProvider);
  if (profile == null || profile.isDemo) return null;

  final prefs = ref.watch(sharedPreferencesProvider);
  final settings = ref.watch(settingsRepositoryProvider);
  final archives = ref.watch(archiveRepositoryProvider);
  final tokens = ref.watch(cameraTokenServiceProvider);
  final dio = ref.watch(bareDioProvider);

  final notifier = FinishPhotoNotifier(
    updates: ref.watch(wsClientProvider).archiveUpdates,
    fetchArchive: archives.byId,
    recentArchives: (printerId) => archives.list(
      limit: FinishPhotoNotifier.archiveLookback,
      printerId: printerId,
    ),
    fetchPicture: (archiveId, filename) => FinishPhotoImage.store(
      baseUrl: profile.baseUrl,
      archiveId: archiveId,
      filename: filename,
      dio: dio,
      token: ({bool forceRefresh = false}) =>
          tokens.token(forceRefresh: forceRefresh),
    ),
    notifications: ref.watch(notificationServiceProvider),
    memory: FinishAlertMemory(prefs),
    // Read per frame rather than captured: this provider outlives a trip to the
    // settings screen, and the switch there is meant to take effect at once.
    isEnabled: () => settings.loadNotificationPrefs().finishPhoto,
  )..start();
  ref.onDispose(notifier.stop);
  return notifier;
});
