import 'dart:async';

import 'package:clock/clock.dart';

import '../../l10n/app_localizations.dart';
import '../api/edge_access_probe.dart';
import '../app_context.dart';
import '../diagnostics/notif_probe.dart';
import '../serial_queue.dart';
import '../settings/settings_repository.dart';
import 'notification_prefs.dart';
import 'notification_service.dart';

/// Alert id band 19 (1–18 are taken, see `billingAlertId`). One notification per
/// install: a second ending replaces the first rather than stacking.
const int edgeSessionAlertId = 19 * alertBandWidth;

final _endings = StreamController<String>.broadcast();
final _recoveries = StreamController<String>.broadcast();

/// The hosts whose session ended, in this isolate, as they are recorded: what
/// the app's banner listens to.
Stream<String> get edgeSessionEndings => _endings.stream;

/// The hosts whose credential Cloudflare accepts again, in this isolate or from
/// the marks another one cleared: what takes the banner down.
Stream<String> get edgeSessionRecoveries => _recoveries.stream;

/// How often an isolate looks at the marks while requests succeed. A mark is
/// read from disk, and every request that gets through reports it.
const edgeAcceptedCheckEvery = Duration(minutes: 1);

/// What happens when Cloudflare stops accepting the credential, a browser session
/// or a service token (#72): the ending is written down where every isolate and
/// the next app open can read it, and the user is told once, because everything
/// behind it (alerts, widgets, the watch) stops with it and nothing else says why.
///
/// Once per ending, not per failed request: the first isolate that can post
/// does, and writes that it did; the rest find it written and return. An isolate
/// that cannot post only records the ending, which is what the banner reads. Both
/// marks are cleared by the next change of the credential, so one that is refused
/// again after signing in again or replacing the token is told again.
class EdgeSessionAlert {
  EdgeSessionAlert({
    required this.settings,
    this.notifications,
    this.l10n = systemAppLocalizations,
  });

  /// Opened afresh each time: another isolate may have written the mark since.
  final Future<SettingsRepository> Function() settings;

  /// Null where an isolate cannot post (the ones a notification button wakes):
  /// the ending is still recorded, and the one that can post tells the user
  /// when it meets it, the banner when the app is next in front.
  final NotificationService? notifications;

  final AppLocalizations Function() l10n;

  var _busy = false;

  /// Makes this the listener of the probe in this isolate.
  void listen() {
    EdgeSessionSignal.listener = (host, token) =>
        unawaited(ended(host, token: token));
    EdgeSessionSignal.acceptedListener = (host) => unawaited(accepted(host));
  }

  DateTime? _acceptedCheckedAt;

  /// Cloudflare let a request with the credential through: if an ending is
  /// recorded for [host], it was not one, and both marks go. A refusal that was
  /// only for a while must not leave a banner up for a token that works, or tell
  /// the user to replace one. Looked at once a minute, not per request, and never
  /// within a minute of the ending: a request that was already on its way when
  /// the refusal came may be one that got through. The time is the ending's own,
  /// kept with it, so it holds whichever isolate found it out and whichever one
  /// asks. The next refusal is told again, as after any change of the credential.
  Future<void> accepted(String host) {
    final now = clock.now();
    final last = _acceptedCheckedAt;
    if (last != null && now.difference(last) < edgeAcceptedCheckEvery) {
      return Future.value();
    }
    _acceptedCheckedAt = now;
    return _queue.run(() => _accepted(host, now));
  }

  Future<void> _accepted(String host, DateTime now) async {
    final store = await settings();
    final ended = store.loadEdgeSessionEnded();
    if (ended == host) {
      final at = store.loadEdgeSessionEndedAt();
      if (at != null && now.difference(at) < edgeAcceptedCheckEvery) return;
      await store.saveEdgeSessionEnded(null);
      // The notification said the alerts were off, and they are not: taken back,
      // so that it does not stay in the tray as a fact that is no longer one.
      await notifications?.cancelAlert(edgeSessionAlertId);
    }
    // Said to the app also when the marks are already clear: another isolate may
    // have cleared them, and the banner only hears this one. Not when they name
    // another host, which is not this one's to take down.
    if (ended == host || ended == null) _recoveries.add(host);
  }

  Future<void> ended(String host, {bool token = false}) {
    // Single-flight in this isolate: every request that was in flight when the
    // session ended reports it, at the same moment.
    if (_busy) return Future.value();
    _busy = true;
    return _queue.run(() async {
      try {
        await _ended(host, token: token);
      } finally {
        _busy = false;
      }
    });
  }

  /// An ending and a recovery read the marks and write them: side by side, one
  /// would act on what the other is in the middle of changing (a refusal found
  /// out while a recovery clears, dropped; a recovery announced for a mark just
  /// written). So they take turns.
  final _queue = SerialQueue();

  Future<void> _ended(String host, {required bool token}) async {
    final store = await settings();
    // Nothing to warn about before there is a server: the setup screen probes
    // with the credential it has just been given, and a wrong one is the
    // user's to see there, not a notification.
    // shortcut: "Change server" keeps the old profile, so a wrong credential
    // typed for the new server still raises it; upgrade if that is reported.
    if (store.loadProfile() == null) return;
    // Told to the app even when another isolate wrote the mark first: this is
    // the one the banner can hear, and a repeat changes nothing for it.
    _endings.add(host);
    // With the time it was found out: whether it is over is judged by that,
    // from whichever isolate asks.
    if (store.loadEdgeSessionEnded() != host) {
      await store.saveEdgeSessionEnded(host, at: clock.now());
    }
    if (notifications == null || store.loadEdgeSessionNotified() == host) {
      return;
    }
    // Claimed before the post, not after: two isolates that find the session
    // ended together (the app going to the background is when both run) would
    // otherwise both pass the check above and ring twice. Given back when the
    // post fails, so that the next request tries again.
    await store.saveEdgeSessionNotified(host);
    try {
      await _post(store, token: token);
    } catch (_) {
      await store.saveEdgeSessionNotified(null);
      rethrow;
    }
  }

  Future<void> _post(SettingsRepository store, {required bool token}) async {
    final service = notifications;
    if (service == null) return;
    final choices = store.loadNotificationPrefs();
    if (!choices.isOn(NotifEvent.edgeSessionEnded)) {
      NotifProbe.suppressed(
        choices.alertsEnabled ? NotifSkip.typeOff : NotifSkip.alertsOff,
        event: NotifEvent.edgeSessionEnded,
      );
      return;
    }
    final l = l10n();
    await service.showAlert(
      event: NotifEvent.edgeSessionEnded,
      // Not about a printer.
      printerId: 0,
      id: edgeSessionAlertId,
      title: token ? l.notifEdgeTokenTitle : l.notifEdgeSessionTitle,
      body: token ? l.notifEdgeTokenBody : l.notifEdgeSessionBody,
      payload: 'edge_session',
    );
  }
}
