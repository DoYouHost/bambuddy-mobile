import 'dart:async';

import 'package:app_util/app_util.dart';
import 'package:flutter/services.dart';

import '../models/inventory.dart';

/// Whether the phone can read an NFC tag right now.
enum NfcStatus {
  ready,

  /// The hardware is there and the user turned NFC off in the system settings.
  disabled,

  /// No NFC hardware, or a build that has none (the watch).
  unsupported,
}

/// The UID of an NFC tag held to the phone (#71). The tags on a spool are linked
/// to it by that number (`tag_uid`), so nothing else is read from them.
abstract class NfcReader {
  Future<NfcStatus> status();

  /// The system's NFC settings, where the user can turn it on.
  Future<void> openSettings();

  /// One UID per tag held to the phone while this stream is listened to, as the
  /// server keys it ([normalizeTagUid]): upper-case hex, the least-significant 16
  /// characters of a longer one. Reading stops with the last listener, and an
  /// error of code `nfc_unavailable` means NFC is off or went off meanwhile. With
  /// no NFC to read ([NfcStatus.unsupported]) the stream is empty and closes at
  /// once.
  Stream<String> tags();
}

/// [NfcReader] over the native channels of `NfcReader.kt`.
class ChannelNfcReader implements NfcReader {
  ChannelNfcReader({PlatformQuery? query, EventChannel? tagsChannel})
    : _query = query ?? const PlatformQuery(_channel),
      _tags = tagsChannel ?? const EventChannel(_tagsChannel);

  static const _channel = MethodChannel(
    'page.codeberg.morganmlgman.bambuddy/nfc',
  );
  static const _tagsChannel = 'page.codeberg.morganmlgman.bambuddy/nfc_tags';

  final PlatformQuery _query;
  final EventChannel _tags;

  /// One stream for every listener. Each `receiveBroadcastStream()` takes over the
  /// channel's message handler, so a second one made while the first is still
  /// listened to would lose its events when the first is cancelled; this one is
  /// counted instead: the host starts reading with the first listener and stops
  /// with the last.
  late final Stream<dynamic> _events = _tags.receiveBroadcastStream();

  @override
  Future<NfcStatus> status() async =>
      switch (await _query.ask<String>('status', fallback: 'unsupported')) {
        'ready' => NfcStatus.ready,
        'disabled' => NfcStatus.disabled,
        _ => NfcStatus.unsupported,
      };

  @override
  Future<void> openSettings() =>
      _query.ask<Object?>('openSettings', fallback: null);

  @override
  Stream<String> tags() async* {
    // An EventChannel with no host on the other end never says so: it reports to
    // the framework's error handler and stays open. Ask first, so a build without
    // NFC ends the stream instead of leaving a listener waiting for ever.
    if (await status() == NfcStatus.unsupported) return;
    yield* _events.transform(
      StreamTransformer<dynamic, String>.fromHandlers(
        handleData: (event, sink) {
          final uid = normalizeTagUid('$event');
          if (uid.isNotEmpty) sink.add(uid);
        },
      ),
    );
  }
}
