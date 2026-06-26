import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/queue_item.dart';
import '../../l10n/app_localizations.dart';
import '../maintenance/maintenance_providers.dart';
import '../queue/queue_providers.dart';

/// Main shell scaffold with bottom navigation bar (Material 3).
/// Displayed for all routes inside [StatefulShellRoute].
class RootScaffold extends ConsumerWidget {
  const RootScaffold({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    // Badge count on "Queue" tab: only PENDING prints (pending/scheduled) —
    // currently printing and paused don't count.
    final queueCount = ref.watch(queueProvider).valueOrNull?.where((i) {
          final k = i.statusKind;
          return k == QueueItemStatusKind.pending ||
              k == QueueItemStatusKind.scheduled;
        }).length ??
        0;

    // Badge count on "Maintenance" tab: sum of overdue tasks (is_due) from all printers.
    final maintenanceCount = ref
            .watch(maintenanceOverviewProvider)
            .valueOrNull
            ?.fold<int>(0, (sum, o) => sum + o.dueCount) ??
        0;

    return Scaffold(
      // Each branch has own Scaffold with AppBar — shell body is branch widget
      // directly, no extra wrapper.
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) => navigationShell.goBranch(
          index,
          // Tap active tab again → return to branch root.
          initialLocation: index == navigationShell.currentIndex,
        ),
        destinations: [
          NavigationDestination(
            icon: _svgIcon('assets/icons/printer_3d.svg', scheme.onSurfaceVariant),
            selectedIcon:
                _svgIcon('assets/icons/printer_3d.svg', scheme.onSecondaryContainer),
            label: l10n.navDashboard,
          ),
          NavigationDestination(
            icon: _badged(const Icon(Icons.list_outlined), queueCount),
            selectedIcon: _badged(const Icon(Icons.list), queueCount),
            label: l10n.navQueue,
          ),
          NavigationDestination(
            icon: const Icon(Icons.inventory_2_outlined),
            selectedIcon: const Icon(Icons.inventory_2),
            label: l10n.navArchive,
          ),
          NavigationDestination(
            icon: _badged(const Icon(Icons.build_outlined), maintenanceCount),
            selectedIcon: _badged(const Icon(Icons.build), maintenanceCount),
            label: l10n.navMaintenance,
          ),
          NavigationDestination(
            icon: _svgIcon(
                'assets/icons/filament_spool.svg', scheme.onSurfaceVariant),
            selectedIcon: _svgIcon(
                'assets/icons/filament_spool.svg', scheme.onSecondaryContainer),
            label: l10n.navFilaments,
          ),
        ],
      ),
    );
  }

  /// Wrap tab icon with badge showing [count]. If [count] == 0, return just icon
  /// (don't show badge). Material 3 `Badge` has rounded squircle shape and
  /// self-positions in top-right.
  Widget _badged(Widget icon, int count) =>
      count > 0 ? Badge(label: Text('$count'), child: icon) : icon;

  /// Icon from own SVG asset (Material lacks sensible 3D printer and spool glyphs).
  /// [color] chosen for bar selection state to behave like normal Material icon
  /// (selected vs unselected).
  Widget _svgIcon(String asset, Color color) => SvgPicture.asset(
        asset,
        width: 24,
        height: 24,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      );
}
