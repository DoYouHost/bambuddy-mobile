import 'package:app_util/app_util.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notifications/hms_catalog.dart';
import '../../data/printers_repository.dart';
import '../../providers.dart';
import '../dashboard/providers.dart';
import '../dashboard/ws_providers.dart';
import 'wall_faults.dart';

/// Holds the screen on through [MainActivity]'s `window` channel
/// (`FLAG_KEEP_SCREEN_ON`). A host without the channel simply lets the screen
/// time out.
class ScreenAwake {
  const ScreenAwake({this.platform = _platform});

  static const _platform = PlatformQuery(
    MethodChannel('page.codeberg.morganmlgman.bambuddy/window'),
  );

  /// Injectable so a test can record what was asked.
  final PlatformQuery platform;

  Future<void> set(bool on) =>
      platform.tell('keepScreenOn', arguments: {'on': on});
}

final screenAwakeProvider = Provider<ScreenAwake>((ref) => const ScreenAwake());

/// The wall-mode setting: whether the wall holds the screen on.
final wallKeepAwakeProvider = NotifierProvider<WallKeepAwakeNotifier, bool>(
  WallKeepAwakeNotifier.new,
);

class WallKeepAwakeNotifier extends Notifier<bool> {
  @override
  bool build() => ref.watch(settingsRepositoryProvider).loadWallKeepAwake();

  Future<void> set(bool on) async {
    await ref.read(settingsRepositoryProvider).saveWallKeepAwake(on);
    state = on;
  }
}

/// The user's expand/collapse choice for the wall panel; null means the screen
/// width decides (D16).
final wallPanelExpandedProvider =
    NotifierProvider<WallPanelExpandedNotifier, bool?>(
      WallPanelExpandedNotifier.new,
    );

class WallPanelExpandedNotifier extends Notifier<bool?> {
  @override
  bool? build() =>
      ref.watch(settingsRepositoryProvider).loadWallPanelExpanded();

  Future<void> set(bool expanded) async {
    await ref.read(settingsRepositoryProvider).saveWallPanelExpanded(expanded);
    state = expanded;
  }
}

/// The wall setting: whether tiles stream their cameras or show status only.
final wallLiveCameraProvider = NotifierProvider<WallLiveCameraNotifier, bool>(
  WallLiveCameraNotifier.new,
);

class WallLiveCameraNotifier extends Notifier<bool> {
  @override
  bool build() => ref.watch(settingsRepositoryProvider).loadWallLiveCamera();

  Future<void> set(bool on) async {
    await ref.read(settingsRepositoryProvider).saveWallLiveCamera(on);
    state = on;
  }
}

/// Printers this device keeps off its wall.
final wallHiddenPrintersProvider =
    NotifierProvider<WallHiddenPrintersNotifier, Set<int>>(
      WallHiddenPrintersNotifier.new,
    );

class WallHiddenPrintersNotifier extends Notifier<Set<int>> {
  @override
  Set<int> build() =>
      ref.watch(settingsRepositoryProvider).loadWallHiddenPrinters();

  Future<void> setShown(int printerId, bool shown) async {
    final next = {...state};
    shown ? next.remove(printerId) : next.add(printerId);
    // State first: two boxes ticked in quick succession must each start from
    // the other's result, not from what was on disk before either.
    state = next;
    await ref.read(settingsRepositoryProvider).saveWallHiddenPrinters(next);
  }
}

/// Every printer the server has, for the wall settings' visibility list —
/// hidden ones included, or there would be no way to show them again.
final wallRosterProvider = Provider.autoDispose<List<PrinterWithStatus>?>((
  ref,
) {
  final roster = ref.watch(dashboardProvider.select((s) => s.printers));
  if (roster == null) return null;
  return withLiveStatuses(roster, ref.watch(printerStatusesProvider));
});

/// The printers on the wall: the dashboard's roster with the live statuses
/// over it, less the ones hidden on this device. Null until the roster first
/// arrives.
///
/// The roster alone is polled once a minute while the socket is up; the live
/// frames are in the statuses map, as on the dashboard.
final wallPrintersProvider = Provider.autoDispose<List<PrinterWithStatus>?>((
  ref,
) {
  final all = ref.watch(wallRosterProvider);
  if (all == null) return null;
  final hidden = ref.watch(wallHiddenPrintersProvider);
  return [
    for (final p in all)
      if (!hidden.contains(p.printer.id)) p,
  ];
});

/// Every active fault on the printers the wall shows, in the order the panel
/// lists them. A printer hidden on this device brings none (D22): the wall is
/// a view, and hiding a printer means not wanting to watch it.
final wallFaultsProvider = Provider.autoDispose<List<WallFault>>(
  (ref) => wallFaults(
    ref.watch(wallPrintersProvider) ?? const [],
    describe: HmsCatalog.instance.describe,
  ),
);
