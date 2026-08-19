import '../notifications/notification_prefs.dart';
import '../notifications/notification_service.dart';
import 'diagnostic_recorder.dart';
import 'log_event.dart';

/// Why an alert the user might have expected did not go out. The names are wire
/// values — the summarising Action groups by them, so renaming one breaks logs
/// already attached to an issue.
enum NotifSkip {
  /// The user turned this event type off.
  typeOff,

  /// The user turned every alert off, which is a different control from
  /// [typeOff] and a different answer to "why didn't I get one".
  alertsOff,

  /// The printer was disconnected. Deliberate: an error on a printer we cannot
  /// reach is not news, and this is not the user having switched anything off.
  offline,

  /// An HMS code the app knows to be an echo of the user's own action, e.g. the
  /// pair a print cancel always emits.
  userAction,

  /// An HMS code with no catalogue description and no server message, or
  /// severity below the notification floor. The firmware emits several such
  /// codes per physical fault; the largest silent drop on the error path.
  undocumented,

  /// The printer came back before the offline grace period expired, so the
  /// pending alert was cancelled rather than posted.
  reconnected,

  /// The server had nothing to say about the printer — either it is unknown or
  /// the call degraded to null. Named for what we know, not for a cause we
  /// cannot tell apart.
  noData,

  /// A maintenance poll failed outright, so no alert could be decided at all.
  fetchFailed,

  /// The printer was still preparing (calibration, layer 0), so its `progress`
  /// described that phase and not the job. Acting on it fires several
  /// milestones at once before the first layer is even down.
  prepPhase,

  /// The same reading already earned an alert recently. Not a decision about
  /// the condition — it still holds — only about saying so again.
  throttled,
}

/// Records what the notification layer decided, and what it decided *not* to
/// do — the useful half is usually a decision not to post, which by definition
/// leaves no trace on the device.
///
/// Stateless and static like the other always-on probes, so an idle app pays
/// nothing and the monitors need no extra constructor argument. In tests the
/// static is null, which keeps the existing fakes silent.
///
/// `title` and `body` never enter a record (`docs/diagnostics-log.md`), which
/// is also why [postError] logs the exception's *class*: the only strings in
/// scope there are the two we may not keep.
class NotifProbe {
  const NotifProbe._();

  /// An alert was handed to the platform — not "shown": it may still be dropped
  /// on permission or a blocked channel, which [openSession] covers. Written
  /// *before* the call is awaited, since most call sites do not await it and a
  /// plugin call that hangs would leave no record of the attempt.
  static void posted({
    required NotifEvent event,
    required int printerId,
    required int nid,
    Map<String, Object?> fields = const {},
  }) =>
      DiagnosticRecorder.active?.add(
        LogSource.notif,
        'posted',
        fields: {
          'event': event.name,
          'printer_id': printerId,
          'nid': nid,
          ...fields,
        },
      );

  /// The platform refused an alert we had already decided to post.
  static void postError({
    required NotifEvent event,
    required int printerId,
    required int nid,
    required Object error,
  }) =>
      DiagnosticRecorder.active?.add(
        LogSource.notif,
        'post_error',
        lvl: LogLevel.error,
        fields: {
          'event': event.name,
          'printer_id': printerId,
          'nid': nid,
          'cause': error.runtimeType.toString(),
        },
      );

  /// What became of the finish photo the server attached to an archive.
  ///
  /// Its own record rather than a [NotifSkip]: this path decides nothing about
  /// *whether* to alert — the alert is already on screen — only whether a photo
  /// reached it, and every way it can fail (no alert to update, the user swiped
  /// it away, the download failed) looks identical from the outside. Ids only;
  /// the print's name stays out of the log as everywhere else here.
  static void finishPhoto({
    required int archiveId,
    required String state,
    int? printerId,
    int? nid,
  }) => DiagnosticRecorder.active?.add(
    LogSource.notif,
    'finish_photo',
    fields: {
      'archive_id': archiveId,
      'printer_id': printerId,
      'nid': nid,
      'state': state,
    },
  );

  /// An alert was not posted, and why.
  ///
  /// [printerId] is null where the decision was not about one printer — a
  /// maintenance poll covers the whole fleet and fails for all of it at once.
  /// [event] is null where no single event type was being decided.
  static void suppressed(
    NotifSkip reason, {
    int? printerId,
    NotifEvent? event,
    Map<String, Object?> fields = const {},
  }) =>
      DiagnosticRecorder.active?.add(
        LogSource.notif,
        'suppressed',
        fields: {
          'event': event?.name,
          'printer_id': printerId,
          'reason': reason.name,
          ...fields,
        },
      );

  /// The baseline a fresh monitor latched from a printer's first frame.
  ///
  /// The background isolate is rebuilt on every entry into the background, and
  /// a new monitor fires nothing from the first frame it sees — otherwise a
  /// print started an hour ago would announce itself as just begun. That
  /// silence is correct, invisible, and the answer to a whole class of "the app
  /// swallowed my notification".
  ///
  /// Not a [suppressed]: at priming no event was evaluated, so calling it a
  /// suppression would describe a decision that never took place.
  static void primed(int printerId, {Map<String, Object?> fields = const {}}) =>
      DiagnosticRecorder.active?.add(
        LogSource.notif,
        'primed',
        fields: {'printer_id': printerId, ...fields},
      );

  /// A print stopped, in whatever state the printer reported — including the
  /// states that produce no alert. `FINISH` and `FAILED` are the only two the
  /// monitor acts on, so everything else (a cancel landing as `IDLE`, an
  /// unknown state, a partial frame) silently drops both the alert *and* the
  /// maintenance reminder hanging off the same branch.
  static void printEnd(int printerId, {String? state, required bool handled}) =>
      DiagnosticRecorder.active?.add(
        LogSource.notif,
        'print_end',
        lvl: handled ? LogLevel.info : LogLevel.warn,
        fields: {'printer_id': printerId, 'state': state},
      );

  /// The ongoing progress notification changed content. One record per change,
  /// not per frame: the monitor already collapses frames whose printer, whole
  /// percent, ETA minute and print count all match, and those are exactly the
  /// fields here. The notification's own text is the job name and stays out.
  static void ongoing({
    required int printerId,
    required int percent,
    int? etaMin,
    required int active,
  }) =>
      DiagnosticRecorder.active?.add(
        LogSource.notif,
        'ongoing',
        fields: {
          'printer_id': printerId,
          'pct': percent,
          'eta_min': etaMin,
          'active': active,
        },
      );

  /// Nothing is printing any more, so the progress notification went back to
  /// neutral. Named `reset` rather than `cleared` because in the foreground
  /// service nothing is removed — the service's own notification is rewritten.
  static void ongoingReset() =>
      DiagnosticRecorder.active?.add(LogSource.notif, 'ongoing_reset');

  /// One maintenance poll: how many items the server reports as due, and how
  /// many of those were new to us. Replaces a record per de-duplicated item,
  /// which would have said the same thing N times.
  static void maintenanceCheck({required int due, required int fresh}) =>
      DiagnosticRecorder.active?.add(
        LogSource.notif,
        'maintenance_check',
        fields: {'due': due, 'fresh': fresh},
      );

  /// The user pressed an action button on a notification. Runs in whichever
  /// isolate the plugin picked — the UI's, the foreground service's, or an
  /// engine spawned for this one callback — and each writes into the stream
  /// that belongs to it, which is why nothing here names an isolate.
  static void action({required String id, required int items}) =>
      DiagnosticRecorder.active?.add(
        LogSource.notif,
        'action',
        fields: {'id': id, 'items': items},
      );

  /// An action did not do what it said it would. `items` names how many of them
  /// were still pending when it broke; null when the whole handler failed.
  static void actionFailed(Object error, {int? items}) =>
      DiagnosticRecorder.active?.add(
        LogSource.notif,
        'action_failed',
        lvl: LogLevel.error,
        fields: {'items': items, 'cause': error.runtimeType.toString()},
      );

  /// There was no server to send the action to — no profile, or credentials the
  /// keystore would not give up. The simplest explanation for "I pressed Mark
  /// Done and the counter never reset".
  static void noClient() => DiagnosticRecorder.active?.add(
        LogSource.notif,
        'no_client',
        lvl: LogLevel.warn,
      );

  /// The notification plugin failed to initialise. Today that failure is an
  /// unobservable rejected future, and every later alert fails while the service
  /// keeps claiming it is monitoring.
  static void initFailed(Object error) =>
      DiagnosticRecorder.active?.add(
        LogSource.notif,
        'init',
        lvl: LogLevel.error,
        fields: {'ok': false, 'cause': error.runtimeType.toString()},
      );

  /// Opens the lane with the state that decides everything else: which event
  /// types the user disabled, whether alerts are off wholesale, whether the OS
  /// permission is granted, and how important the alerts channel is.
  ///
  /// One line instead of a record per suppressed event, and it works even when
  /// the recording covers none of the moments an alert was due — prints run for
  /// hours, a session is capped at `recordingLimit`.
  ///
  /// [permission] and [channelImportance] are injected so this is testable;
  /// both may answer null, logged as an absent field rather than as a guess. A
  /// granted permission with a muted channel is a real configuration and looks
  /// identical from `areNotificationsEnabled` alone.
  static Future<void> openSession(
    NotificationPrefs prefs, {
    Future<bool?> Function()? permission,
    Future<int?> Function()? channelImportance,
  }) async {
    if (DiagnosticRecorder.active == null) return;
    final granted = await _quietly(permission);
    final importance = await _quietly(channelImportance);
    DiagnosticRecorder.active?.add(
      LogSource.notif,
      'prefs',
      fields: {
        'off': [
          for (final event in NotifEvent.values)
            if (!prefs.enabled.contains(event)) event.name,
        ],
        'alerts': prefs.alertsEnabled,
        'perm': granted,
        'chan_imp': importance,
      },
    );
  }

  /// A platform read that must never be the reason a recording has no snapshot.
  static Future<T?> _quietly<T>(Future<T?> Function()? read) async {
    if (read == null) return null;
    try {
      return await read();
    } on Object {
      return null;
    }
  }
}

/// Records every alert the app hands to the platform. One decorator rather than
/// a log call at each site, so it cannot be forgotten in new code.
///
/// Wraps the *outer* service in the foreground-service isolate, not the
/// `LocalNotificationService` inside it: that isolate's `showOngoing` rewrites
/// the service notification instead of delegating, so wrapping from underneath
/// would miss it. Unused in the UI isolate, where the ongoing methods are
/// no-ops and a record would be a fabrication.
class LoggingNotifications implements NotificationService {
  const LoggingNotifications(this._inner);

  final NotificationService _inner;

  @override
  Future<void> init() => _inner.init();

  @override
  Future<bool> requestPermission() => _inner.requestPermission();

  @override
  Future<void> showOngoing({
    required String title,
    required String body,
    required int progress,
  }) =>
      _inner.showOngoing(title: title, body: body, progress: progress);

  @override
  Future<void> clearOngoing() => _inner.clearOngoing();

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
  }) {
    NotifProbe.posted(event: event, printerId: printerId, nid: id);
    return _inner
        .showAlert(
      event: event,
      printerId: printerId,
      id: id,
      title: title,
      body: body,
      payload: payload,
      actions: actions,
      picture: picture,
    )
        // Rethrown with its original stack: absorbing it would remove an error
        // that today reaches the isolate's uncaught handler and gets its own
        // record from `ErrorProbe`.
        .catchError((Object error, StackTrace stack) {
      NotifProbe.postError(
        event: event,
        printerId: printerId,
        nid: id,
        error: error,
      );
      Error.throwWithStackTrace(error, stack);
    });
  }

  @override
  Future<bool> isAlertActive(int id) => _inner.isAlertActive(id);
}
