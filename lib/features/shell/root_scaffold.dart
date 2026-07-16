import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/queue_item.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../maintenance/maintenance_providers.dart';
import '../queue/queue_providers.dart';

/// Main shell scaffold with the modernized ("2a") bottom navigation bar.
/// Displayed for all routes inside [StatefulShellRoute].
class RootScaffold extends ConsumerWidget {
  const RootScaffold({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);

    // Badge count on "Queue" tab: only PENDING prints (pending/scheduled).
    final queueCount = ref.watch(queueProvider).valueOrNull?.where((i) {
          final k = i.statusKind;
          return k == QueueItemStatusKind.pending ||
              k == QueueItemStatusKind.scheduled;
        }).length ??
        0;

    // Badge count on "Maintenance" tab: sum of overdue tasks from all printers.
    final maintenanceCount = ref
            .watch(maintenanceOverviewProvider)
            .valueOrNull
            ?.fold<int>(0, (sum, o) => sum + o.dueCount) ??
        0;

    final index = navigationShell.currentIndex;
    void go(int i) => navigationShell.goBranch(i, initialLocation: i == index);

    final items = [
      _NavItem(
        icon: _svgIcon('assets/icons/printer_3d.svg'),
        label: l10n.navDashboard,
        selected: index == 0,
        tokens: t,
        onTap: () => go(0),
      ),
      _NavItem(
        icon: const Icon(Icons.list_outlined, size: 22),
        selectedIcon: const Icon(Icons.list, size: 22),
        label: l10n.navQueue,
        selected: index == 1,
        badge: queueCount,
        tokens: t,
        onTap: () => go(1),
      ),
      _NavItem(
        icon: const Icon(Icons.inventory_2_outlined, size: 22),
        selectedIcon: const Icon(Icons.inventory_2, size: 22),
        label: l10n.navArchive,
        selected: index == 2,
        tokens: t,
        onTap: () => go(2),
      ),
      _NavItem(
        icon: const Icon(Icons.build_outlined, size: 22),
        selectedIcon: const Icon(Icons.build, size: 22),
        label: l10n.navMaintenance,
        selected: index == 3,
        badge: maintenanceCount,
        tokens: t,
        onTap: () => go(3),
      ),
      _NavItem(
        icon: _svgIcon('assets/icons/filament_spool.svg'),
        label: l10n.navFilaments,
        selected: index == 4,
        tokens: t,
        onTap: () => go(4),
      ),
    ];

    return DashBackground(
      child: Scaffold(
      backgroundColor: Colors.transparent,
      // Each branch has its own Scaffold with AppBar — shell body is the branch
      // widget directly, no extra wrapper.
      body: navigationShell,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: t.navBar,
          border: Border(top: BorderSide(color: t.hairline)),
        ),
        // Reserve the system nav bar inset via viewPadding (constant, unlike
        // padding, which the keyboard collapses to 0) so the tab bar never
        // overlaps the system nav buttons while a field is focused. SafeArea
        // still guards the left/right edges (landscape notch).
        child: SafeArea(
          top: false,
          bottom: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                8, 12, 8, 10 + MediaQuery.of(context).viewPadding.bottom),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [for (final it in items) Expanded(child: it)],
            ),
          ),
        ),
      ),
    ),
    );
  }

  /// Icon from own SVG asset (Material lacks 3D-printer / spool glyphs). Color is
  /// applied by [_NavItem] via a wrapping IconTheme, so pass a plain glyph here.
  Widget _svgIcon(String asset) => _SvgGlyph(asset: asset);
}

/// SVG glyph that tints itself from the ambient [IconTheme] color, so it behaves
/// like a Material [Icon] inside [_NavItem].
class _SvgGlyph extends StatelessWidget {
  const _SvgGlyph({required this.asset});

  final String asset;

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color ?? const Color(0xFFFFFFFF);
    return SvgPicture.asset(
      asset,
      width: 22,
      height: 22,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}

/// Single bottom-nav item: icon + label, green when selected, dimmed otherwise.
/// Optional [badge] draws a small count in the top-right corner of the icon.
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.tokens,
    required this.onTap,
    this.selectedIcon,
    this.badge = 0,
  });

  final Widget icon;
  final Widget? selectedIcon;
  final String label;
  final bool selected;
  final DashTokens tokens;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final color = selected ? tokens.accentGreenInk : tokens.textTertiary;
    final glyph = selected ? (selectedIcon ?? icon) : icon;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 24,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  IconTheme.merge(
                    data: IconThemeData(color: color, size: 22),
                    child: glyph,
                  ),
                  if (badge > 0)
                    Positioned(
                      top: -5,
                      right: -8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        constraints:
                            const BoxConstraints(minWidth: 15, minHeight: 15),
                        decoration: BoxDecoration(
                          color: tokens.danger,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            '$badge',
                            style: const TextStyle(
                              fontFamily: DashTokens.fontUi,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              height: 1.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: DashTokens.fontUi,
                fontSize: 10,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
