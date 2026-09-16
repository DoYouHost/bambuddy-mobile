import 'dart:convert';

import 'package:clock/clock.dart';

import '../core/settings/server_profile.dart';
import '../core/settings/settings_repository.dart';
import 'wear_transport.dart';

/// The last fleet the watch was shown, so a cold start has something to paint
/// while the first poll is still out.
///
/// That wait is the whole reason this exists: the relay gives the phone 4 s to
/// answer, or 15 s once it acks that it is booting an engine, and only then
/// falls back to REST. Everything the app does before `runApp` adds up to a
/// fraction of that, so the spinner — not the engine — is what a cold start
/// feels like.
///
/// What is stored is the **wire map**, not the models. `PrinterStatus` is read
/// through several dozen tolerant converters and declared `createToJson: false`,
/// so the only spelling of a fleet that survives a save and a load is the one
/// the server sent — which is also the one [wearFleetFromJson] already reads.
class WearFleetCache {
  WearFleetCache(
    this._settings, {
    this.minInterval = const Duration(minutes: 1),
  });

  final SettingsRepository _settings;

  /// Floor between writes. A poll lands every 5 s while something is printing,
  /// and all this cache owes the next cold start is *a* recent frame — a
  /// 60-second-old one opens exactly as fast as a 5-second-old one, and the
  /// difference is invisible behind the dimming the screens apply to both.
  final Duration minInterval;

  DateTime? _lastWrite;

  /// Stores [fleet] against [profile]. A no-op for anything with no wire map
  /// behind it — the REST path and demo mode both arrive that way.
  ///
  /// Never throws: a cache that could not be written is not a failed poll, and
  /// the caller is on the path that just succeeded.
  Future<void> save(WearFleet fleet, ServerProfile? profile) async {
    final raw = fleet.raw;
    if (raw == null || profile == null) return;
    final now = clock.now();
    final last = _lastWrite;
    if (last != null && now.difference(last) < minInterval) return;
    try {
      await _settings.saveWearFleetCache(
        jsonEncode({_urlKey: profile.baseUrl, _fleetKey: raw}),
      );
      // Stamped only once it is written. Stamping before the write booked the
      // whole [minInterval] for an attempt that failed, so "the next poll tries
      // again" — which is what this catch relies on — was false for a minute.
      _lastWrite = now;
    } on Object {
      // Nothing to tell and nobody to tell it to; the next poll tries again.
    }
  }

  /// The stored fleet when it belongs to [profile], else null.
  ///
  /// The URL is checked rather than trusted: the watch adopts a server the
  /// phone pushes at it ([WearApp]), and a fleet cached against the previous
  /// one would open on printers that are not there.
  ///
  /// An empty fleet is treated as no cache at all. Painting "no printers" from
  /// last time is a worse answer than the spinner it replaces — the spinner is
  /// at least honest about not knowing yet.
  WearFleet? load(ServerProfile? profile) {
    if (profile == null) return null;
    final stored = _settings.loadWearFleetCache();
    if (stored == null) return null;
    try {
      final decoded = jsonDecode(stored);
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded[_urlKey] != profile.baseUrl) return null;
      final fleet = decoded[_fleetKey];
      if (fleet is! Map<String, dynamic>) return null;
      final restored = wearFleetFromJson(fleet, stale: true);
      return restored.printers.isEmpty ? null : restored;
    } on Object {
      // Corrupt or written by a version that spelled this differently — the
      // poll that is already on its way is the answer.
      return null;
    }
  }

  static const _urlKey = 'baseUrl';
  static const _fleetKey = 'fleet';
}
