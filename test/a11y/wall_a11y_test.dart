import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/features/dashboard/providers.dart';
import 'package:bambuddy_mobile/features/queue/queue_providers.dart';
import 'package:bambuddy_mobile/features/wall/wall_providers.dart';
import 'package:bambuddy_mobile/features/wall/wall_screen.dart';
import 'package:bambuddy_mobile/features/wall/wall_tile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/queue/queue_fakes.dart';
import '../helpers.dart';
import 'a11y_harness.dart';

/// Rendered contrast and touch targets of wall mode on a landscape phone: the
/// camera tiles on the demo's frames, the rail, the panel's farm and settings
/// views, status-only tiles, faults on a tile and in the panel, and the empty
/// states. Not covered: the live MJPEG stream and its snapshot fallback with the
/// "live paused" pill (they need a camera socket); the camera screen a tile
/// opens is in camera_a11y_test.dart.

/// Every printer of the demo fleet hidden, which is what the wall settings'
/// checkboxes do one tap at a time.
class _AllHidden extends WallHiddenPrintersNotifier {
  @override
  Set<int> build() => {1, 2, 3, 4, 5, 6};
}

/// A roster of one printing printer with a fault, over the demo server (so the
/// tile draws the demo's camera frame under its fault pill).
final _faultRoster = [
  fixedDashboardOverride(
    const DashboardState(
      printers: [
        PrinterWithStatus(
          printer: Printer(id: 1, name: 'X1 Carbon', model: 'X1C'),
          status: PrinterStatus(
            id: 1,
            connected: true,
            state: 'RUNNING',
            progress: 42,
            remainingTime: 50,
            layerNum: 110,
            totalLayers: 264,
            hmsErrors: [
              HmsError(
                message: 'Filament has run out.',
                code: '0x8004',
                attr: 0x03008004,
                module: 3,
                severity: 3,
                fullCode: '03008004',
              ),
              HmsError(
                message: 'The nozzle temperature is abnormal.',
                code: '0x10001',
                attr: 0x07008001,
                module: 7,
                severity: 1,
                fullCode: '0700800100010001',
              ),
            ],
          ),
        ),
      ],
    ),
  ),
  inertStatusesOverride,
];

/// One wall surface on a landscape phone, the shape wall mode is designed for
/// (docs/tv-flavor.md D15).
void _wall(
  String name, {
  List<Override> overrides = const [],
  Future<void> Function(WidgetTester tester)? arrange,
  required Finder shows,
}) => a11ySurface(
  'wall, $name',
  window: landscapeRedmi,
  home: () => const WallScreen(),
  overrides: overrides,
  arrange: arrange,
  shows: shows,
);

void main() {
  // The default on a phone: camera tiles and the collapsed rail.
  _wall('camera tiles, rail', shows: byLogId('wall.tile'));

  _wall(
    'panel, farm',
    arrange: (tester) => a11yTap(tester, byLogId('wall.panel_expand')),
    shows: byLogId('wall.panel_collapse'),
  );
  _wall(
    'panel, settings',
    arrange: (tester) => a11yTap(tester, byLogId('wall.settings')),
    shows: byLogId('wall.keep_awake'),
  );
  _wall(
    'status tiles, live camera off',
    arrange: (tester) async {
      await a11yTap(tester, byLogId('wall.settings'));
      await a11yTap(tester, byLogId('wall.live_camera'));
      await a11yTap(tester, byLogId('wall.settings'));
    },
    shows: find.byType(WallTile),
  );
  _wall(
    'faults on a tile and in the panel',
    overrides: _faultRoster,
    arrange: (tester) => a11yTap(tester, byLogId('wall.panel_expand')),
    shows: find.text(pl.wallErrorsTitle),
  );
  _wall(
    'fault on a status tile, rail with a fault count',
    overrides: _faultRoster,
    arrange: (tester) async {
      await a11yTap(tester, byLogId('wall.settings'));
      await a11yTap(tester, byLogId('wall.live_camera'));
      await a11yTap(tester, byLogId('wall.settings'));
    },
    shows: find.byType(WallTile),
  );
  _wall(
    'empty queue in the panel',
    overrides: [queueProvider.overrideWith(FakeQueue.new)],
    arrange: (tester) => a11yTap(tester, byLogId('wall.panel_expand')),
    shows: find.text(pl.queueEmpty),
  );
  _wall(
    'every printer hidden',
    overrides: [wallHiddenPrintersProvider.overrideWith(_AllHidden.new)],
    shows: find.text(pl.wallAllHidden),
  );
  _wall(
    'no printers on the server',
    overrides: [fixedDashboardOverride(const DashboardState(printers: []))],
    shows: find.text(pl.noPrinters),
  );
}
