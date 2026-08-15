import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'notification_prefs.dart';
import 'notification_service.dart';

/// What a print-ended alert was posted with, kept so the same notification can
/// be re-posted later with the finish photo added to it.
class PostedAlert {
  const PostedAlert({
    required this.event,
    required this.printerId,
    required this.id,
    required this.title,
    required this.body,
    required this.postedAt,
    this.payload,
  });

  final NotifEvent event;
  final int printerId;
  final int id;
  final String title;
  final String body;
  final DateTime postedAt;
  final String? payload;

  Map<String, dynamic> toJson() => {
    'event': event.name,
    'printerId': printerId,
    'id': id,
    'title': title,
    'body': body,
    'payload': payload,
    'postedAt': postedAt.millisecondsSinceEpoch,
  };

  /// Null for anything this version cannot read — an entry written by a newer
  /// build, or one whose event name no longer exists.
  static PostedAlert? fromJson(Object? json) {
    if (json is! Map) return null;
    final eventName = json['event']?.toString();
    final event = NotifEvent.values
        .where((e) => e.name == eventName)
        .firstOrNull;
    final printerId = json['printerId'];
    final id = json['id'];
    final postedAt = json['postedAt'];
    if (event == null || printerId is! int || id is! int || postedAt is! int) {
      return null;
    }
    return PostedAlert(
      event: event,
      printerId: printerId,
      id: id,
      title: json['title']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      payload: json['payload']?.toString(),
      postedAt: DateTime.fromMillisecondsSinceEpoch(postedAt),
    );
  }
}

/// The last print-ended alert per printer, in `SharedPreferences`.
///
/// It has to survive an isolate, not just outlive a function: the alert is
/// posted by the foreground-service isolate, and by the time the finish photo
/// lands the user may have opened the app — which stops that service and leaves
/// the UI isolate, with no memory of what was posted, as the only one able to
/// update the notification. Prefs is the one thing both of them read.
///
/// Only print-ended events are kept, one entry per printer, and only for as long
/// as a photo could still arrive for them.
class FinishAlertMemory {
  const FinishAlertMemory(this._prefs, {this.window = const Duration(minutes: 20)});

  final SharedPreferences _prefs;

  /// How long an entry stays useful. Beyond it the notification is stale enough
  /// that a photo arriving now belongs to a different print.
  final Duration window;

  static const _key = 'finish_alert_last';

  /// The events a finish photo can be attached to. A failed print is the one
  /// where the photo is worth the most — it shows what went wrong.
  static const events = {NotifEvent.printFinished, NotifEvent.printFailed};

  Future<void> remember(PostedAlert alert) async {
    if (!events.contains(alert.event)) return;
    final all = await _read();
    all.removeWhere((_, a) => _expired(a, alert.postedAt));
    all['${alert.printerId}'] = alert;
    await _prefs.setString(
      _key,
      jsonEncode({for (final e in all.entries) e.key: e.value.toJson()}),
    );
  }

  /// The alert still worth updating for [printerId] at [now], or null.
  Future<PostedAlert?> recall(int printerId, DateTime now) async {
    final alert = (await _read())['$printerId'];
    if (alert == null || _expired(alert, now)) return null;
    return alert;
  }

  /// Every alert still inside the window, in no particular order — the work
  /// list for the poll that goes looking for photos the server never announces.
  Future<List<PostedAlert>> recallAll(DateTime now) async => [
    for (final alert in (await _read()).values)
      if (!_expired(alert, now)) alert,
  ];

  /// Drops the entry once its notification has been updated — the photo is on
  /// it, and the server's later "upgraded" shot for the same print would
  /// otherwise re-post a notification the user may have dismissed in between.
  Future<void> forget(int printerId) async {
    final all = await _read();
    if (all.remove('$printerId') == null) return;
    await _prefs.setString(
      _key,
      jsonEncode({for (final e in all.entries) e.key: e.value.toJson()}),
    );
  }

  bool _expired(PostedAlert alert, DateTime now) =>
      now.difference(alert.postedAt) > window;

  /// Re-reads the platform before every access. The two isolates that use this
  /// hold separate in-memory copies of `SharedPreferences`, so the entry the
  /// service just wrote is invisible to the app's copy — the same trap the
  /// maintenance "dirty" flag documents.
  Future<Map<String, PostedAlert>> _read() async {
    await _prefs.reload();
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final out = <String, PostedAlert>{};
      decoded.forEach((key, value) {
        final alert = PostedAlert.fromJson(value);
        if (alert != null) out['$key'] = alert;
      });
      return out;
    } on Object {
      return {};
    }
  }
}

/// Wraps a [NotificationService] so every print-ended alert it posts is written
/// to [FinishAlertMemory] on the way through.
///
/// A decorator rather than a call inside `PrintMonitor`: the monitor has ten
/// alert methods and no reason to know that two of them are photo-worthy, and
/// this way the record is written from the one place the alert actually goes
/// out — including the paths (a re-post, a probe) that never touch the monitor.
class RememberingNotifications implements NotificationService {
  const RememberingNotifications(this._inner, this._memory, this._now);

  final NotificationService _inner;
  final FinishAlertMemory _memory;
  final DateTime Function() _now;

  @override
  Future<void> init() => _inner.init();

  @override
  Future<bool> requestPermission() => _inner.requestPermission();

  @override
  Future<void> showOngoing({
    required String title,
    required String body,
    required int progress,
  }) => _inner.showOngoing(title: title, body: body, progress: progress);

  @override
  Future<void> clearOngoing() => _inner.clearOngoing();

  @override
  Future<bool> isAlertActive(int id) => _inner.isAlertActive(id);

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
  }) async {
    await _inner.showAlert(
      event: event,
      printerId: printerId,
      id: id,
      title: title,
      body: body,
      payload: payload,
      actions: actions,
      picture: picture,
    );
    // A post that already carries the photo is the update itself; remembering
    // it would arm the very path that produced it.
    if (picture != null) return;
    await _memory.remember(
      PostedAlert(
        event: event,
        printerId: printerId,
        id: id,
        title: title,
        body: body,
        payload: payload,
        postedAt: _now(),
      ),
    );
  }
}
