import 'dart:async';

import '../api/ws_messages.dart';
import '../diagnostics/notif_probe.dart';
import '../models/archive.dart';
import 'finish_alert_memory.dart';
import 'notification_service.dart';

/// Puts the server's finish photo onto the print-ended notification that is
/// already on screen: the alert goes out when the printer reports the print
/// over, the photo exists a minute or so later, so this finds the alert the
/// print left behind ([FinishAlertMemory]) and re-posts it, same id, with the
/// picture. Android replaces the notification in place and a paired watch gets
/// the update over the same bridge that carried the original.
///
/// **Two ways in, because the server announces only one of them.** An
/// `archive_updated` frame carrying `photo_added` is sent from exactly one place
/// (`main.py::_upgrade_finish_photo_from_timelapse`), reached only when a print
/// recorded a timelapse whose video was still in transit. The ordinary capture —
/// every other finished print — is written straight to `archive.photos` with
/// nothing on the wire, which is why [poll] has to go looking while an alert is
/// live; the frame is kept as the fast path for the case it does cover.
///
/// Nothing here is load-bearing: no alert, a notification already swiped away, a
/// download that failed — each ends quietly and leaves the text-only one as is.
class FinishPhotoNotifier {
  FinishPhotoNotifier({
    required this._updates,
    required this._fetchArchive,
    required this._recentArchives,
    required this._fetchPicture,
    required this._notifications,
    required this._memory,
    required this._isEnabled,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final Stream<WsArchiveUpdated> _updates;
  final Future<Archive?> Function(int archiveId) _fetchArchive;

  /// The printer's latest archives. A list rather than the single newest one:
  /// the server orders by `created_at`, which a reprint does not touch (it
  /// reuses the original row), so the print that just ended can sit behind
  /// anything created since — see [runForAlert].
  final Future<List<Archive>> Function(int printerId) _recentArchives;
  final Future<AlertPicture?> Function(int archiveId, String filename)
  _fetchPicture;
  final NotificationService _notifications;
  final FinishAlertMemory _memory;
  final bool Function() _isEnabled;
  final DateTime Function() _now;

  static const pollInterval = Duration(minutes: 1);

  /// How many of a printer's archives to look at when finding the print that
  /// just ended. Only rows created after it can push it down the list, and that
  /// takes new files uploaded in the same quarter of an hour.
  static const archiveLookback = 10;

  /// Matches the server's own ceiling for replacing the live grab with a frame
  /// off the timelapse (`_FINISH_PHOTO_UPGRADE_TIMEOUT_SECONDS`, 900 s): past
  /// it, nothing further is coming for this print.
  static const pollWindow = Duration(minutes: 15);

  StreamSubscription<WsArchiveUpdated>? _sub;
  Timer? _timer;

  /// Serializes the work — a frame and a poll can land on the same print at
  /// once, and two runs would race over one notification.
  Future<void> _pending = Future.value();

  void start() {
    _sub ??= _updates.listen((frame) {
      // Never carry an error forward: a rejected future here would poison every
      // frame after it and re-throw out of [stop], which runs inside
      // `PrintMonitorTaskHandler.onDestroy` before the socket's own teardown.
      _pending = _pending
          .then((_) => _handleFrame(frame))
          .catchError((Object error) => _failed(frame.archiveId, error));
    });
    _timer ??= Timer.periodic(pollInterval, (_) {
      _pending = _pending
          .then((_) => poll())
          .catchError((Object error) => _failed(0, error));
    });
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await _sub?.cancel();
    _sub = null;
    // Bounded, because this is awaited inside
    // `PrintMonitorTaskHandler.onDestroy` ahead of the socket's dispose and the
    // recording's flush: a poll against an unreachable server sits on Dio's
    // connect and receive timeouts. Whatever is in flight finishes on its own —
    // nothing after this depends on it.
    await _pending.timeout(const Duration(seconds: 2), onTimeout: () {});
  }

  /// One sweep over the alerts still live: for each, ask whether its print has
  /// a photo now. Driven by a timer; public so a test can step it.
  ///
  /// Reads the work list from [FinishAlertMemory] rather than from a callback on
  /// the alert, so an app opened mid-window takes the search over from the
  /// background service that started it — the entry outlives the isolate.
  Future<void> poll() async {
    if (!_isEnabled()) return;
    final now = _now();
    for (final alert in await _memory.recallAll(now)) {
      if (now.difference(alert.postedAt) > pollWindow) continue;
      // Per printer, so one unreachable lookup does not end the sweep for the
      // others and leave them unserved for the rest of the window.
      try {
        final archive = runForAlert(
          await _recentArchives(alert.printerId),
          alert,
        );
        final filename = archive == null
            ? null
            : finishPhotoIn(archive.photos);
        if (archive == null || filename == null) continue;
        await _attach(archive.id, filename, alert);
      } on Object catch (error) {
        _failed(0, error, printerId: alert.printerId);
      }
    }
  }

  /// Which of [recent] is the print [alert] was posted for, or null when none
  /// of them fits.
  ///
  /// Never the first: the server orders by `created_at`, which a reprint leaves
  /// on the original print because it reuses that archive row. `completed_at`
  /// moves with the run, so it is the one to match — and requiring it near the
  /// alert is what puts no photo, rather than a wrong one, on a notification
  /// when nothing here belongs to this print.
  static Archive? runForAlert(List<Archive> recent, PostedAlert alert) {
    Archive? best;
    for (final archive in recent) {
      final ended = archive.completedAt;
      if (ended == null) continue;
      if (ended.difference(alert.postedAt).abs() > pollWindow) continue;
      if (best == null || ended.isAfter(best.completedAt!)) best = archive;
    }
    return best;
  }

  /// The newest shot the server itself took, out of everything hanging off the
  /// archive, or null when there is none.
  ///
  /// Neither end of the list is the answer — captures and uploads append, the
  /// timelapse upgrade prepends, and a reused row keeps every run's photos. The
  /// name each capture path builds does order them: `finish_<YYYYMMDD>_<HHMMSS>`
  /// sorts chronologically as text. Uploads carry no such name and are skipped;
  /// this is about the shot the printer took, not the user's own.
  static String? finishPhotoIn(List<String> photos) {
    String? best;
    for (final name in photos) {
      if (!name.startsWith('finish_')) continue;
      if (best == null || name.compareTo(best) > 0) best = name;
    }
    return best;
  }

  Future<void> _handleFrame(WsArchiveUpdated frame) async {
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
      await _attach(frame.archiveId, filename, alert);
    } on Object catch (error) {
      // This runs off a stream in an isolate whose uncaught errors kill nothing
      // but this feature — and would take the socket's listener with them.
      _failed(frame.archiveId, error);
    }
  }

  /// Re-posts [alert] with the photo, unless the notification is already gone.
  Future<void> _attach(int archiveId, String filename, PostedAlert alert) async {
    if (!await _notifications.isAlertActive(alert.id)) {
      await _memory.forget(alert.printerId);
      NotifProbe.finishPhoto(
        archiveId: archiveId,
        printerId: alert.printerId,
        nid: alert.id,
        state: 'dismissed',
      );
      return;
    }
    final picture = await _fetchPicture(archiveId, filename);
    if (picture == null) {
      // Kept in memory on purpose: the next poll (or the upgraded shot's own
      // frame) is another chance at the same notification.
      NotifProbe.finishPhoto(
        archiveId: archiveId,
        printerId: alert.printerId,
        nid: alert.id,
        state: 'fetch_failed',
      );
      return;
    }
    await _notifications.showAlert(
      event: alert.event,
      printerId: alert.printerId,
      id: alert.id,
      title: alert.title,
      body: alert.body,
      payload: alert.payload,
      picture: picture,
    );
    await _memory.forget(alert.printerId);
    NotifProbe.finishPhoto(
      archiveId: archiveId,
      printerId: alert.printerId,
      nid: alert.id,
      state: 'attached',
    );
  }

  void _failed(int archiveId, Object error, {int? printerId}) =>
      NotifProbe.finishPhoto(
        archiveId: archiveId,
        printerId: printerId,
        state: 'failed:${error.runtimeType}',
      );
}
