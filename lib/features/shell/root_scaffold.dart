import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';

/// Główny szkielet powłoki z dolną belką nawigacyjną (Material 3).
/// Wyświetlany dla wszystkich tras wewnątrz [StatefulShellRoute].
class RootScaffold extends StatelessWidget {
  const RootScaffold({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      // Każda gałąź ma swój własny Scaffold z AppBar — ciało powłoki
      // to bezpośrednio widget gałęzi, bez dodatkowego opakowania.
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) => navigationShell.goBranch(
          index,
          // Ponowne kliknięcie aktywnej zakładki → wróć do korzenia gałęzi.
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
            icon: const Icon(Icons.list_outlined),
            selectedIcon: const Icon(Icons.list),
            label: l10n.navQueue,
          ),
          NavigationDestination(
            icon: const Icon(Icons.inventory_2_outlined),
            selectedIcon: const Icon(Icons.inventory_2),
            label: l10n.navArchive,
          ),
          NavigationDestination(
            icon: const Icon(Icons.build_outlined),
            selectedIcon: const Icon(Icons.build),
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

  /// Ikona z własnego assetu SVG (Material nie ma sensownych glifów drukarki 3D
  /// ani szpuli). [color] dobierany pod stan zaznaczenia belki, by zachować się
  /// jak zwykła ikona Material (zaznaczona vs nie).
  Widget _svgIcon(String asset, Color color) => SvgPicture.asset(
        asset,
        width: 24,
        height: 24,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      );
}
