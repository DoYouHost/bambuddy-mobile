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

  /// An HMS code with no description in the catalogue and no server message, or
  /// severity below the notification floor. The firmware emits several
  /// undocumented codes per physical fault; this is the largest silent drop on
  /// the error path.
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

  /// The printer was still preparing (calibration, layer 0), so the `progress`
  /// it reported described that phase and not the job. Deliberate: acting on it
  /// fires several milestones at once before the first layer is even down.
  prepPhase,
}

/// Records what the notification layer decided, and what it decided *not* to do.
///
/// Four reports this answers: "the app buried me in notifications", "they arrive
/// at the wrong time", "I got the wrong notification", and the mirror image "I got
/// none when I should have". A posted alert is only half of that — the useful half
/// is usually a decision not to post, which by definition leaves no trace on the
/// device.
///
/// Stateless and static, like `HttpProbe`: every method reads
/// `DiagnosticRecorder.active` per call, so an idle app pays nothing and the
/// monitors need no extra constructor argument. In tests the static is null, which
/// is what keeps the existing fakes silent.
///
/// ## What never enters a record
///
/// `title` and `body`. They carry `_jobLabel` — the user's model and file name —
/// or the printer's name, and this log is uploaded to a public issue. The event
/// type, the printer id and our own notification id say which notification it was
/// without quoting anything the user typed. Same reason [postError] logs the
/// exception's *class* and not its message: the only strings in scope there are
/// the two we are not allowed to keep.
class NotifProbe {
  const NotifProbe._();

  /// An alert was handed to the platform.
  ///
  /// "Handed to", not "shown": the platform may still drop it (permission,
  /// blocked channel), which is what the session snapshot in [openSession] is
  /// for. Written *before* the call is awaited, because eleven of the thirteen
  /// call sites do not await it — a plugin call that hangs would otherwise leave
  /// no record of the attempt.
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
  /// The background isolate is rebuilt on every entry into the background, and a
  /// new monitor deliberately fires nothing from the first frame it sees —
  /// otherwise a print that started an hour ago would announce itself as just
  /// begun. That silence is correct and invisible, and it is the answer to a
  /// whole class of "the app swallowed my notification". One record per printer
  /// says what was taken as already-happened.
  ///
  /// Not a [suppressed]: at priming no event was evaluated, so calling it a
  /// suppression would describe a decision that never took place.
  static void primed(int printerId, {Map<String, Object?> fields = const {}}) =>
      DiagnosticRecorder.active?.add(
        LogSource.notif,
        'primed',
        fields: {'printer_id': printerId, ...fields},
      );

  /// A print stopped, in whatever state the printer reported.
  ///
  /// Unconditional, including the states that produce no alert at all. `FINISH`
  /// and `FAILED` are the only two the monitor acts on, so everything else — a
  /// user cancel landing as `IDLE`, an unknown state, a partial frame — silently
  /// drops both the alert *and* the maintenance reminder that hangs off the same
  /// branch. This is the cheapest record in the lane and it explains more
  /// reports than any other.
  static void printEnd(int printerId, {String? state, required bool handled}) =>
      DiagnosticRecorder.active?.add(
        LogSource.notif,
        'print_end',
        lvl: handled ? LogLevel.info : LogLevel.warn,
        fields: {'printer_id': printerId, 'state': state},
      );

  /// The ongoing progress notification changed content.
  ///
  /// One record per change, not per frame: the monitor already collapses frames
  /// whose printer, whole percent, ETA minute and print count all match, so this
  /// fires a handful of times a minute during a print. The fields are the ones
  /// that make up that key — the notification's own text is the job name and
  /// stays out.
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

  /// The user pressed an action button on a notification.
  ///
  /// Runs in whichever isolate the plugin picked: the UI's if the app is open, the
  /// foreground service's if it is backgrounded, or a dedicated engine spawned for
  /// this one callback if the app is gone. All three end up writing into the
  /// stream that belongs to them, which is why nothing here names an isolate.
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
  /// keystore would not give up. Was a bare `return`, and it is the simplest
  /// explanation for "I pressed Mark Done and the counter never reset".
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
  /// This is the cheap answer to the whole "I did not get a notification"
  /// class — one line instead of a record per suppressed event, and it works
  /// even when the recording covers none of the moments an alert was due. Prints
  /// run for hours; a session is capped at five minutes.
  ///
  /// [permission] and [channelImportance] are injected rather than called
  /// straight from the plugin so this is testable; both may answer null, which is
  /// logged as an absent field rather than as a guess. A granted permission with
  /// a muted channel is a real configuration and looks identical from
  /// `areNotificationsEnabled` alone, which is why the importance is here too.
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

/// Records every alert the app hands to the platform.
///
/// One decorator instead of a line in each implementation, and instead of a line
/// at each of the thirteen call sites: this is the single place both production
/// services funnel through, so it cannot be forgotten in new code the way a
/// manual log call would be.
///
/// Wraps the *outer* service in the foreground-service isolate, not the
/// `LocalNotificationService` inside it — the isolate's own `showOngoing`
/// deliberately does not delegate (it rewrites the service notification instead),
/// so wrapping from underneath would miss it. Not used in the UI isolate at all:
/// there the ongoing methods are no-ops, so a record would be a fabrication.
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
    )
        // Rethrown with its original stack: this must record a failure, not
        // absorb one. Most call sites do not await the future, so absorbing it
        // here would quietly remove an error that today reaches the isolate's
        // uncaught handler — and gets its own record from `ErrorProbe`.
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
}
