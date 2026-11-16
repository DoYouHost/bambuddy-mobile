import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../data/inventory_source.dart';
import '../../data/server_settings_repository.dart';
import '../../features/notifications/low_stock.dart';
import '../api/api_exceptions.dart';
import '../models/inventory.dart';

/// What one look at the inventory brings back.
typedef LowStockRead = ({
  List<Spool> spools,
  List<SpoolAssignment> assignments,
  Map<String, dynamic> settings,
});

/// Asks the server which spools in AMS slots are low, for the service isolate,
/// which has no providers to ask through.
///
/// One look at a time: a burst of `inventory_changed` frames (a weight sync
/// writes one per spool) costs one request round and, if anything arrived
/// meanwhile, one more.
class LowStockFeed {
  LowStockFeed({
    required this._read,
    required this.onSlots,
    required this.onUnavailable,
  });

  /// The spools, assignments and settings of whichever backend the server runs.
  /// The backend is decided once: the service lives only while the app is in
  /// the background, and a server that switches mode meanwhile is not worth a
  /// probe on every look.
  factory LowStockFeed.overDio(
    Dio dio, {
    required void Function(Map<LowStockKey, LowStockSlot> slots) onSlots,
    required void Function() onUnavailable,
  }) {
    final settings = ServerSettingsRepository(dio);
    InventoryBackend? backend;
    return LowStockFeed(
      onSlots: onSlots,
      onUnavailable: onUnavailable,
      read: () async {
        final chosen = backend ??= await detectInventoryBackend(dio);
        final SpoolInventorySource source = switch (chosen) {
          InventoryBackend.native => NativeInventorySource(dio),
          InventoryBackend.spoolman => SpoolmanInventorySource(dio),
        };
        // One after the other, not `(a, b, c).wait`: that wraps whatever failed
        // in a `ParallelWaitError`, which is not the refusal the caller tells
        // from a bad moment, and the fallback to the phone's rule would never
        // happen.
        final spools = await source.fetchSpools();
        final assignments = await source.fetchAssignments();
        final serverSettings = await settings.fetch();
        return (
          spools: spools,
          assignments: assignments,
          // A session that may not read the settings gets the flags instead,
          // which carry this one number.
          settings: serverSettings.containsKey(lowStockThresholdKey)
              ? serverSettings
              : await settings.fetchUiFlags(),
        );
      },
    );
  }

  final Future<LowStockRead> Function() _read;

  /// The slots as the server's rule sees them, after every look that worked.
  final void Function(Map<LowStockKey, LowStockSlot> slots) onSlots;

  /// This session cannot read the inventory at all: refused (403) or no such
  /// route on an older server (404). Said again on every look that finds it so.
  final void Function() onUnavailable;

  bool _looking = false;
  bool _again = false;
  bool _stopped = false;

  /// Whether [stop] has been called, for the service's teardown test.
  @visibleForTesting
  bool get stopped => _stopped;

  /// The service is going: a look still in flight delivers nothing and none
  /// starts, so no alert is posted from a monitor already disposed.
  void stop() {
    _stopped = true;
    _again = false;
  }

  /// Looks now, or as soon as the look in flight is over. A failure that is not
  /// a refusal (no network, a 5xx) says nothing: the next frame or tick looks
  /// again, and what was said before stays said.
  Future<void> refresh() async {
    if (_stopped) return;
    if (_looking) {
      _again = true;
      return;
    }
    _looking = true;
    try {
      do {
        _again = false;
        await _look();
      } while (_again);
    } finally {
      _looking = false;
    }
  }

  Future<void> _look() async {
    final LowStockRead data;
    try {
      data = await _read();
    } on AppApiException catch (e) {
      if (_stopped) return;
      final refused = e is AuthException && e.code == AppErrorCode.forbidden;
      if (refused || e.statusCode == 404) onUnavailable();
      return;
    }
    if (_stopped) return;
    onSlots(
      lowStockSlots(
        spools: data.spools,
        assignments: data.assignments,
        globalThreshold: lowStockThresholdFrom(data.settings),
      ),
    );
  }
}
