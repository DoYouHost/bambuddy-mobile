import 'dart:async';
import 'dart:io';

import 'package:clock/clock.dart';

import '../api/ws_messages.dart';
import '../diagnostics/notif_probe.dart';
import '../models/archive.dart';
import 'finish_alert_memory.dart';
import 'notification_prefs.dart';
import 'notification_service.dart';

/// Puts the server's finish photo onto the print-ended notification that is already
/// on screen: finds the alert the print left behind ([FinishAlertMemory]) and re-posts
/// it, same id, with the picture. Two ways in, because the server announces only one
/// of them. Nothing here is load-bearing: each failure ends quietly and leaves the
/// text-only alert. It also puts the outcome buttons on it ([addOutcome])
/// (docs/notification-delivery.md, "The finish photo").
class FinishPhotoNotifier {
  FinishPhotoNotifier({
    required this._updates,
    required this._fetchArchive,
    required this._recentArchives,
    required this._fetchPicture,
    required this._notifications,
    required this._memory,
    required this._isEnabled,
  });

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
    // Bounded: this is awaited in `onDestroy` ahead of the socket's dispose
    // (docs/notification-delivery.md, "The finish photo").
    await _pending.timeout(const Duration(seconds: 2), onTimeout: () {});
  }

  /// One sweep over the alerts still live: for each, ask whether its print has a photo
  /// now. Driven by a timer; public so a test can step it. Reads its work list from
  /// [FinishAlertMemory], so an app opened mid-window takes the search over.
  Future<void> poll() async {
    if (!_isEnabled()) return;
    final now = clock.now();
    for (final alert in await _memory.recallAll(now)) {
      if (now.difference(alert.postedAt) > pollWindow) continue;
      // Per printer, so one unreachable lookup does not end the sweep for the
      // others and leave them unserved for the rest of the window.
      try {
        final archive = runForAlert(
          await _recentArchives(alert.printerId),
          alert,
        );
        final filename = archive == null ? null : finishPhotoIn(archive.photos);
        if (archive == null || filename == null) continue;
        await _attach(archive.id, filename, alert);
      } on Object catch (error) {
        _failed(0, error, printerId: alert.printerId);
      }
    }
  }

  /// Which of [recent] is the print [alert] was posted for, or null: matched on
  /// `completed_at`, never the first, since a reprint reuses the archive row
  /// (docs/notification-delivery.md, "The finish photo").
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

  /// The newest shot the server itself took, or null: ordered by the
  /// `finish_<YYYYMMDD>_<HHMMSS>` name, since neither end of the list is the answer;
  /// uploads are skipped (docs/notification-delivery.md, "The finish photo").
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
      final alert = await _memory.recall(printerId, clock.now());
      // One with a photo already on it: this is the server's later
      // "upgraded" shot, and re-posting would bring back a notification the
      // user may have dismissed in between.
      if (alert == null || alert.picture != null) {
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

  /// Whether the notification is gone, dropping the memory entry and recording
  /// it when so — asked on both sides of the download, hence its own method.
  Future<bool> _gone(int archiveId, PostedAlert alert) async {
    if (await _notifications.isAlertActive(alert.id)) return false;
    await _memory.forget(alert.printerId);
    NotifProbe.finishPhoto(
      archiveId: archiveId,
      printerId: alert.printerId,
      nid: alert.id,
      state: 'dismissed',
    );
    return true;
  }

  /// Re-posts [alert] with the photo, unless the notification is already gone.
  Future<void> _attach(
    int archiveId,
    String filename,
    PostedAlert alert,
  ) async {
    if (await _gone(archiveId, alert)) return;
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
    // Asked again after the download, which can run most of a minute: a swiped-away
    // alert would be brought back and ring a second time. The entry is re-read too, since
    // the other isolate may have added the outcome buttons meanwhile.
    final current = await _memory.recall(alert.printerId, clock.now()) ?? alert;
    if (current.id != alert.id || await _gone(archiveId, current)) return;
    await _notifications.showAlert(
      event: current.event,
      printerId: current.printerId,
      id: current.id,
      title: current.title,
      body: current.body,
      payload: current.payload,
      // The outcome buttons, when they got here first.
      actions: current.actions,
      picture: picture,
    );
    // Kept, with the photo on it, rather than dropped: the outcome buttons
    // may still come and have to re-post the photo along with them.
    await _memory.remember(current.copyWith(picture: picture));
    NotifProbe.finishPhoto(
      archiveId: archiveId,
      printerId: alert.printerId,
      nid: alert.id,
      state: 'attached',
    );
  }

  /// Puts the outcome buttons (#1898) on the print-finished alert for [printerId], if
  /// it is still on screen; false means the caller asks with a notification of its own.
  /// Through the same queue as the photo (docs/notification-delivery.md, "The finish photo").
  Future<bool> addOutcome({
    required int archiveId,
    required int printerId,
    required String payload,
    required List<NotificationAction> actions,
  }) {
    final added = Completer<bool>();
    _pending = _pending
        .then((_) async {
          added.complete(
            await _addOutcome(archiveId, printerId, payload, actions),
          );
        })
        .catchError((Object error) {
          if (!added.isCompleted) added.complete(false);
          _failed(archiveId, error, printerId: printerId);
        });
    return added.future;
  }

  Future<bool> _addOutcome(
    int archiveId,
    int printerId,
    String payload,
    List<NotificationAction> actions,
  ) async {
    final now = clock.now();
    final alert = await _memory.recall(printerId, now);
    // The question comes a minute or so after the print ends; an alert older
    // than the photo's own window belongs to an earlier print.
    if (alert == null ||
        alert.event != NotifEvent.printFinished ||
        now.difference(alert.postedAt) > pollWindow) {
      return false;
    }
    if (await _gone(archiveId, alert)) return false;
    final picture = _stillOnDisk(alert.picture);
    final updated = alert.copyWith(
      payload: payload,
      actions: actions,
      picture: picture,
      clearPicture: picture == null,
    );
    await _notifications.showAlert(
      event: updated.event,
      printerId: updated.printerId,
      id: updated.id,
      title: updated.title,
      body: updated.body,
      payload: updated.payload,
      actions: updated.actions,
      picture: updated.picture,
      quiet: true,
    );
    await _memory.remember(updated);
    NotifProbe.finishPhoto(
      archiveId: archiveId,
      printerId: printerId,
      nid: updated.id,
      state: 'outcome_added',
    );
    return true;
  }

  /// The photo files are the app's cache; one cleared since would make the
  /// plugin refuse the whole post, so the notification goes without it.
  static AlertPicture? _stillOnDisk(AlertPicture? picture) =>
      picture == null || !File(picture.photoPath).existsSync() ? null : picture;

  void _failed(int archiveId, Object error, {int? printerId}) =>
      NotifProbe.finishPhoto(
        archiveId: archiveId,
        printerId: printerId,
        state: 'failed:${error.runtimeType}',
      );
}
