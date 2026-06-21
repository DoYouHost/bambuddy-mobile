import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/queue_item.dart';
import '../../l10n/app_localizations.dart';
import '../maintenance/maintenance_providers.dart';
import '../queue/queue_providers.dart';

/// Główny szkielet powłoki z dolną belką nawigacyjną (Material 3).
/// Wyświetlany dla wszystkich tras wewnątrz [StatefulShellRoute].
class RootScaffold extends ConsumerWidget {
  const RootScaffold({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    // Licznik plakietki na zakładce „Kolejka": tylko wydruki OCZEKUJĄCE
    // (pending/scheduled) — aktualnie drukowany i wstrzymane się nie liczą.
    final queueCount = ref.watch(queueProvider).valueOrNull?.where((i) {
          final k = i.statusKind;
          return k == QueueItemStatusKind.pending ||
              k == QueueItemStatusKind.scheduled;
        }).length ??
        0;

    // Licznik na zakładce „Konserwacja": suma przeterminowanych czynności
    // (is_due) ze wszystkich drukarek.
    final maintenanceCount = ref
            .watch(maintenanceOverviewProvider)
            .valueOrNull
            ?.fold<int>(0, (sum, o) => sum + o.dueCount) ??
        0;

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

  /// Owija ikonę zakładki plakietką z liczbą [count]. Gdy [count] == 0 zwraca
  /// samą ikonę (plakietki nie pokazujemy). `Badge` z Material 3 ma kształt
  /// zaokrąglonego squircle'a i sam pozycjonuje się w prawym górnym rogu.
  Widget _badged(Widget icon, int count) =>
      count > 0 ? Badge(label: Text('$count'), child: icon) : icon;

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
