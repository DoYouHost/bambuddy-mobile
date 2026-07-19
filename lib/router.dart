import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/about/about_screen.dart';
import 'features/archive/archive_screen.dart';
import 'features/dashboard/add_printer_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/files/file_manager_screen.dart';
import 'features/files/trash_screen.dart';
import 'features/gcode/gcode_viewer_screen.dart';
import 'features/inventory/inventory_screen.dart';
import 'features/maintenance/maintenance_screen.dart';
import 'features/maintenance/maintenance_settings.dart';
import 'features/makerworld/makerworld_screen.dart';
import 'features/notifications/notification_settings_screen.dart';
import 'features/projects/projects_screen.dart';
import 'features/projects/project_detail_screen.dart';
import 'features/settings/cloud_account_screen.dart';
import 'features/queue/queue_screen.dart';
import 'features/setup/setup_screen.dart';
import 'features/shell/root_scaffold.dart';
import 'features/stats/statistics_screen.dart';
import 'features/swatches/swatches_screen.dart';
import 'providers.dart';

/// Main navigator key — allows pushing screens (e.g. spool scanner triggered
/// from home widget) outside widget tree.
final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Navigator keys for each shell branch.
final _dashboardNavigatorKey   = GlobalKey<NavigatorState>(debugLabel: 'dashboard');
final _queueNavigatorKey       = GlobalKey<NavigatorState>(debugLabel: 'queue');
final _archiveNavigatorKey     = GlobalKey<NavigatorState>(debugLabel: 'archive');
final _maintenanceNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'maintenance');
final _inventoryNavigatorKey   = GlobalKey<NavigatorState>(debugLabel: 'inventory');

/// App router with bottom navigation bar shell (Material 3).
/// /setup route stays outside shell — shown without NavigationBar.
final routerProvider = Provider<GoRouter>((ref) {
  final hasProfile =
      ref.watch(serverProfileProvider.select((p) => p != null));
  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: hasProfile ? '/' : '/setup',
    redirect: (context, state) {
      if (!hasProfile && state.matchedLocation != '/setup') {
        return '/setup';
      }
      return null;
    },
    routes: [
      // Server setup screen — outside shell, no navigation bar.
      GoRoute(path: '/setup', builder: (_, _) => const SetupScreen()),

      // Add printer — full screen outside shell (pushed from the dashboard).
      GoRoute(
        path: '/printers/add',
        builder: (_, _) => const AddPrinterScreen(),
      ),

      // Notification settings — full screen outside shell (pushed from dashboard).
      GoRoute(
        path: '/settings/notifications',
        builder: (_, _) => const NotificationSettingsScreen(),
      ),

      // Maintenance settings (types + per-printer overrides) — full screen
      // outside shell (pushed from the Maintenance status screen's gear).
      GoRoute(
        path: '/settings/maintenance',
        builder: (_, _) => const MaintenanceSettingsScreen(),
      ),

      // Archive statistics — full screen outside shell (pushed from drawer).
      GoRoute(
        path: '/stats',
        builder: (_, _) => const StatisticsScreen(),
      ),

      // File manager (library) — full screen outside shell (pushed from drawer).
      // Trash as subroute.
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

      // MakerWorld — model import; full screen outside shell (pushed from drawer).
      GoRoute(
        path: '/makerworld',
        builder: (_, _) => const MakerWorldScreen(),
      ),

      // Projects — group prints toward a goal; full screen outside shell
      // (pushed from drawer). Detail as subroute by id.
      GoRoute(
        path: '/projects',
        builder: (_, _) => const ProjectsScreen(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (_, state) {
              // Malformed id (e.g. deep link /projects/abc) → don't crash the
              // route builder; bounce back to the list instead.
              final id = int.tryParse(state.pathParameters['id'] ?? '');
              if (id == null) return const ProjectsScreen();
              return ProjectDetailScreen(projectId: id);
            },
          ),
        ],
      ),

      // Filament swatch codes — full screen outside shell (pushed from drawer).
      GoRoute(
        path: '/swatches',
        builder: (_, _) => const SwatchesScreen(),
      ),

      // Bambu Cloud account (login for MakerWorld downloads) — in settings;
      // full screen outside shell (pushed from drawer or import).
      GoRoute(
        path: '/settings/cloud',
        builder: (_, _) => const CloudAccountScreen(),
      ),

      // About + licenses — full screen outside shell (pushed from drawer).
      GoRoute(
        path: '/about',
        builder: (_, _) => const AboutScreen(),
      ),

      // G-code viewer (WebView) — full screen outside shell. Source in query:
      // `archive` or `library_file` (+ optionally `plate`); `name` sets title.
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

      // Shell with bottom navigation bar — three tabs as branches.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            RootScaffold(navigationShell: navigationShell),
        branches: [
          // Tab 0: Dashboard
          StatefulShellBranch(
            navigatorKey: _dashboardNavigatorKey,
            routes: [
              GoRoute(path: '/', builder: (_, _) => const DashboardScreen()),
            ],
          ),
          // Tab 1: Queue
          StatefulShellBranch(
            navigatorKey: _queueNavigatorKey,
            routes: [
              GoRoute(path: '/queue', builder: (_, _) => const QueueScreen()),
            ],
          ),
          // Tab 2: Archive
          StatefulShellBranch(
            navigatorKey: _archiveNavigatorKey,
            routes: [
              GoRoute(
                path: '/archive',
                builder: (_, _) => const ArchiveScreen(),
              ),
            ],
          ),
          // Tab 3: Maintenance
          StatefulShellBranch(
            navigatorKey: _maintenanceNavigatorKey,
            routes: [
              GoRoute(
                path: '/maintenance',
                builder: (_, _) => const MaintenanceScreen(),
              ),
            ],
          ),
          // Tab 4: Filaments (spool inventory)
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
  // "Change server" (profile set→null→set) rebuilds a new GoRouter — dispose
  // the old one so its listeners don't leak.
  ref.onDispose(router.dispose);
  return router;
});
