import 'dart:async';

import '../api/ws_messages.dart';
import '../diagnostics/notif_probe.dart';
import '../models/archive.dart';
import 'finish_alert_memory.dart';
import 'notification_service.dart';

/// Puts the server's finish photo onto the print-ended notification that is
/// already on screen.
///
/// The two halves never arrive together: the alert goes out the moment the
/// printer reports the print over, while the server is still capturing the shot
/// from the camera — it announces the result seconds to minutes later with an
/// `archive_updated` frame. So this listens for that frame, finds the alert the
/// print left behind ([FinishAlertMemory]) and re-posts it, same id, with the
/// photo attached. Android replaces the notification in place, and a paired
/// watch gets the update through the same bridge that carried the original.
///
/// Everything it does is optional by construction: no alert to update, a
/// notification the user already swiped away, a download that failed — each ends
/// the run quietly and leaves the text-only notification exactly as it was.
class FinishPhotoNotifier {
  FinishPhotoNotifier({
    required this._updates,
    required this._fetchArchive,
    required this._fetchPicture,
    required this._notifications,
    required this._memory,
    required this._isEnabled,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final Stream<WsArchiveUpdated> _updates;
  final Future<Archive?> Function(int archiveId) _fetchArchive;
  final Future<AlertPicture?> Function(int archiveId, String filename)
  _fetchPicture;
  final NotificationService _notifications;
  final FinishAlertMemory _memory;
  final bool Function() _isEnabled;
  final DateTime Function() _now;

  StreamSubscription<WsArchiveUpdated>? _sub;

  /// Serializes the frames: the server sends a second one for the same print
  /// when it upgrades the live grab to a frame off the timelapse, and two
  /// overlapping runs would race over the same notification.
  Future<void> _pending = Future.value();

  void start() {
    _sub ??= _updates.listen((frame) {
      _pending = _pending.then((_) => _handle(frame));
    });
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    await _pending;
  }

  Future<void> _handle(WsArchiveUpdated frame) async {
    final filename = frame.photoAdded;
    if (filename == null) return;
    if (!_isEnabled()) {
      NotifProbe.finishPhoto(archiveId: frame.archiveId, state: 'disabled');
      return;
    }
    try {
      final printerId = (await _fetchArchive(frame.archiveId))?.printerId;
      if (printerId == null) {
        NotifProbe.finishPhoto(archiveId: frame.archiveId, state: 'no_printer');
        return;
      }
      final alert = await _memory.recall(printerId, _now());
      if (alert == null) {
        // The ordinary case for anything the user was not alerted about: an
        // archive that gained a photo for a print this device never announced.
        NotifProbe.finishPhoto(
          archiveId: frame.archiveId,
          printerId: printerId,
          state: 'no_alert',
        );
        return;
      }
      if (!await _notifications.isAlertActive(alert.id)) {
        await _memory.forget(printerId);
        NotifProbe.finishPhoto(
          archiveId: frame.archiveId,
          printerId: printerId,
          nid: alert.id,
          state: 'dismissed',
        );
        return;
      }
      final picture = await _fetchPicture(frame.archiveId, filename);
      if (picture == null) {
        // Kept in memory on purpose: the upgraded shot arrives as its own frame
        // and is a second chance at the same notification.
        NotifProbe.finishPhoto(
          archiveId: frame.archiveId,
          printerId: printerId,
          nid: alert.id,
          state: 'fetch_failed',
        );
        return;
      }
      await _notifications.showAlert(
        event: alert.event,
        printerId: printerId,
        id: alert.id,
        title: alert.title,
        body: alert.body,
        payload: alert.payload,
        picture: picture,
      );
      await _memory.forget(printerId);
      NotifProbe.finishPhoto(
        archiveId: frame.archiveId,
        printerId: printerId,
        nid: alert.id,
        state: 'attached',
      );
    } on Object catch (error) {
      // This runs off a stream in an isolate whose uncaught errors kill nothing
      // but this feature — and would take the socket's listener with them.
      NotifProbe.finishPhoto(
        archiveId: frame.archiveId,
        state: 'failed:${error.runtimeType}',
      );
    }
  }
}
