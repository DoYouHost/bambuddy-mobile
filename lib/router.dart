import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/about/about_screen.dart';
import 'features/archive/archive_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/files/file_manager_screen.dart';
import 'features/files/trash_screen.dart';
import 'features/gcode/gcode_viewer_screen.dart';
import 'features/inventory/inventory_screen.dart';
import 'features/maintenance/maintenance_screen.dart';
import 'features/makerworld/makerworld_screen.dart';
import 'features/notifications/notification_settings_screen.dart';
import 'features/settings/cloud_account_screen.dart';
import 'features/queue/queue_screen.dart';
import 'features/setup/setup_screen.dart';
import 'features/shell/root_scaffold.dart';
import 'features/stats/statistics_screen.dart';
import 'features/swatches/swatches_screen.dart';
import 'providers.dart';

/// Klucz głównego nawigatora — pozwala pchać ekrany (np. skaner szpuli
/// wyzwolony z widgetu ekranu głównego) spoza drzewa widgetów.
final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Klucze nawigatorów dla każdej gałęzi powłoki.
final _dashboardNavigatorKey   = GlobalKey<NavigatorState>(debugLabel: 'dashboard');
final _queueNavigatorKey       = GlobalKey<NavigatorState>(debugLabel: 'queue');
final _archiveNavigatorKey     = GlobalKey<NavigatorState>(debugLabel: 'archive');
final _maintenanceNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'maintenance');
final _inventoryNavigatorKey   = GlobalKey<NavigatorState>(debugLabel: 'inventory');

/// Router aplikacji z powłoką dolnej belki nawigacyjnej (Material 3).
/// Trasa /setup pozostaje poza powłoką — wyświetlana bez NavigationBar.
final routerProvider = Provider<GoRouter>((ref) {
  final hasProfile =
      ref.watch(serverProfileProvider.select((p) => p != null));
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: hasProfile ? '/' : '/setup',
    redirect: (context, state) {
      if (!hasProfile && state.matchedLocation != '/setup') {
        return '/setup';
      }
      return null;
    },
    routes: [
      // Ekran konfiguracji serwera — poza powłoką, bez belki nawigacyjnej.
      GoRoute(path: '/setup', builder: (_, _) => const SetupScreen()),

      // Ustawienia powiadomień — pełny ekran poza powłoką (push z dashboardu).
      GoRoute(
        path: '/settings/notifications',
        builder: (_, _) => const NotificationSettingsScreen(),
      ),

      // Statystyki archiwum — pełny ekran poza powłoką (push z szuflady).
      GoRoute(
        path: '/stats',
        builder: (_, _) => const StatisticsScreen(),
      ),

      // Menedżer plików (biblioteka) — pełny ekran poza powłoką (push
      // z szuflady). Kosz jako podtrasa.
      GoRoute(
        path: '/files',
        builder: (_, _) => const FileManagerScreen(),
        routes: [
          GoRoute(
            path: 'trash',
            builder: (_, _) => const TrashScreen(),
          ),
        ],
      ),

      // MakerWorld — import modeli; pełny ekran poza powłoką (push z szuflady).
      GoRoute(
        path: '/makerworld',
        builder: (_, _) => const MakerWorldScreen(),
      ),

      // Kody próbek filamentów — pełny ekran poza powłoką (push z szuflady).
      GoRoute(
        path: '/swatches',
        builder: (_, _) => const SwatchesScreen(),
      ),

      // Konto chmury Bambu (logowanie do pobierania z MakerWorld) — w
      // ustawieniach; pełny ekran poza powłoką (push z szuflady lub z importu).
      GoRoute(
        path: '/settings/cloud',
        builder: (_, _) => const CloudAccountScreen(),
      ),

      // O aplikacji + licencje — pełny ekran poza powłoką (push z szuflady).
      GoRoute(
        path: '/about',
        builder: (_, _) => const AboutScreen(),
      ),

      // Przeglądarka G-code (WebView) — pełny ekran poza powłoką. Źródło w
      // query: `archive` lub `library_file` (+ opcjonalnie `plate`); `name`
      // ustawia tytuł paska.
      GoRoute(
        path: '/gcode-viewer',
        builder: (_, state) {
          final q = state.uri.queryParameters;
          return GcodeViewerScreen(
            archiveId: int.tryParse(q['archive'] ?? ''),
            libraryFileId: int.tryParse(q['library_file'] ?? ''),
            plate: int.tryParse(q['plate'] ?? ''),
            title: q['name'],
          );
        },
      ),

      // Powłoka z dolną belką nawigacyjną — trzy zakładki jako gałęzie.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            RootScaffold(navigationShell: navigationShell),
        branches: [
          // Zakładka 0: Dashboard
          StatefulShellBranch(
            navigatorKey: _dashboardNavigatorKey,
            routes: [
              GoRoute(path: '/', builder: (_, _) => const DashboardScreen()),
            ],
          ),
          // Zakładka 1: Kolejka
          StatefulShellBranch(
            navigatorKey: _queueNavigatorKey,
            routes: [
              GoRoute(path: '/queue', builder: (_, _) => const QueueScreen()),
            ],
          ),
          // Zakładka 2: Archiwum
          StatefulShellBranch(
            navigatorKey: _archiveNavigatorKey,
            routes: [
              GoRoute(
                path: '/archive',
                builder: (_, _) => const ArchiveScreen(),
              ),
            ],
          ),
          // Zakładka 3: Konserwacja
          StatefulShellBranch(
            navigatorKey: _maintenanceNavigatorKey,
            routes: [
              GoRoute(
                path: '/maintenance',
                builder: (_, _) => const MaintenanceScreen(),
              ),
            ],
          ),
          // Zakładka 4: Filamenty (magazyn szpul)
          StatefulShellBranch(
            navigatorKey: _inventoryNavigatorKey,
            routes: [
              GoRoute(
                path: '/inventory',
                builder: (_, _) => const InventoryScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
