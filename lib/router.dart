import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/diagnostics/navigation_probe.dart';
import 'features/about/about_screen.dart';
import 'features/admin/admin_screen.dart';
import 'features/admin/api_keys_screen.dart';
import 'features/admin/group_detail_screen.dart';
import 'features/admin/groups_screen.dart';
import 'features/admin/users_screen.dart';
import 'features/archive/archive_photos_screen.dart';
import 'features/archive/archive_screen.dart';
import 'features/archive/timelapse_editor_screen.dart';
import 'features/archive/timelapse_screen.dart';
import 'features/bug_report/bug_report_screen.dart';
import 'features/bug_report/recording_banner.dart';
import 'features/dashboard/add_printer_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/files/file_manager_screen.dart';
import 'features/files/trash_screen.dart';
import 'features/gcode/gcode_viewer_route.dart';
import 'features/gcode/gcode_viewer_screen.dart';
import 'features/inventory/inventory_screen.dart';
import 'features/maintenance/maintenance_screen.dart';
import 'features/maintenance/maintenance_settings.dart';
import 'features/makerworld/makerworld_screen.dart';
import 'features/notifications/notification_settings_screen.dart';
import 'features/print_log/print_log_screen.dart';
import 'features/projects/projects_screen.dart';
import 'features/projects/project_detail_screen.dart';
import 'features/settings/cloud_account_screen.dart';
import 'features/queue/queue_screen.dart';
import 'features/setup/setup_screen.dart';
import 'features/shell/root_scaffold.dart';
import 'features/pipelines/pipelines_screen.dart';
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
  // Diagnostic log: the probe follows the location, and a `ModalObserver` per
  // navigator catches what is pushed over a screen (a sheet opened inside a tab
  // goes on that tab's navigator). Both must exist before the router —
  // observers cannot be added afterwards — and both log only while a recording
  // runs. One observer instance per navigator: Flutter asserts that.
  final probe = NavigationProbe();
  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    observers: [ModalObserver()],
    initialLocation: hasProfile ? '/' : '/setup',
    redirect: (context, state) {
      // The bug report stays reachable without a profile: a setup that fails is
      // exactly what someone needs to report, and the recorder runs fine with no
      // server — the header simply carries no fingerprint.
      const openWithoutProfile = {'/setup', bugReportRoute};
      if (!hasProfile && !openWithoutProfile.contains(state.matchedLocation)) {
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

      // Bug report — full screen outside shell (pushed from drawer, and from
      // the recording bar when a session is finished elsewhere).
      GoRoute(
        path: bugReportRoute,
        builder: (_, _) => const BugReportScreen(),
      ),

      // Archive statistics — full screen outside shell (pushed from drawer).
      GoRoute(
        path: '/stats',
        builder: (_, _) => const StatisticsScreen(),
      ),

      // Slicer pipelines — full screen outside shell (pushed from drawer).
      // The runs dashboard is pushed from it rather than routed: it is only
      // ever reached through a pipeline, and a deep link to it on a server
      // without the routes would land on an error.
      GoRoute(
        path: '/pipelines',
        builder: (_, _) => const PipelinesScreen(),
      ),

      // Print log — per-run history, full screen outside shell (opened from the
      // archive's menu and from the Stats failure card).
      GoRoute(
        path: '/print-log',
        builder: (_, _) => const PrintLogScreen(),
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

      // Administration hub — full screen outside shell (pushed from the
      // drawer, shown there only to an identity holding one of the three read
      // permissions). Each screen below is reachable on its own, so a deep
      // link still works; the hub is what the drawer offers.
      GoRoute(
        path: '/admin',
        builder: (_, _) => const AdminScreen(),
      ),

      // Accounts on the server, gated on `users:read`.
      GoRoute(
        path: '/admin/users',
        builder: (_, _) => const UsersScreen(),
      ),

      // API keys — credentials for everything that is not this app.
      GoRoute(
        path: '/admin/api-keys',
        builder: (_, _) => const ApiKeysScreen(),
      ),

      // Groups (permission sets + who holds them), gated on `groups:read`.
      GoRoute(
        path: '/admin/groups',
        builder: (_, _) => const GroupsScreen(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (_, state) {
              // A malformed id (a stale deep link) goes back to the list
              // rather than crashing the route builder.
              final id = int.tryParse(state.pathParameters['id'] ?? '');
              if (id == null) return const GroupsScreen();
              return GroupDetailScreen(groupId: id);
            },
          ),
        ],
      ),

      // About + licenses — full screen outside shell (pushed from drawer).
      GoRoute(
        path: '/about',
        builder: (_, _) => const AboutScreen(),
      ),

      // G-code viewer (WebView) — full screen outside shell. Source in query:
      // `archive` or `library_file` (+ optionally `plate`); `name` sets title.
      // Links to it are built by `gcodeViewerRoute`, which owns these names.
      GoRoute(
        path: gcodeViewerPath,
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

      // Timelapse player — full screen outside shell. `archive` is required;
      // `name` sets the title. Malformed ids fall back to the archive list
      // rather than opening a player with nothing to play.
      GoRoute(
        path: '/timelapse',
        redirect: (_, state) =>
            int.tryParse(state.uri.queryParameters['archive'] ?? '') == null
            ? '/archive'
            : null,
        builder: (_, state) {
          final q = state.uri.queryParameters;
          return TimelapseScreen(
            archiveId: int.parse(q['archive']!),
            title: q['name'],
          );
        },
      ),

      // Photos of a finished print — same shape as the timelapse route above.
      GoRoute(
        path: '/archive/photos',
        redirect: (_, state) =>
            int.tryParse(state.uri.queryParameters['archive'] ?? '') == null
            ? '/archive'
            : null,
        builder: (_, state) {
          final q = state.uri.queryParameters;
          return ArchivePhotosScreen(
            archiveId: int.parse(q['archive']!),
            title: q['name'],
          );
        },
      ),

      // Trim/speed editor for a timelapse, pushed from the player. Pops `true`
      // when the server re-encoded, which is the player's cue to reload.
      GoRoute(
        path: '/timelapse/edit',
        redirect: (_, state) =>
            int.tryParse(state.uri.queryParameters['archive'] ?? '') == null
            ? '/archive'
            : null,
        builder: (_, state) {
          final q = state.uri.queryParameters;
          return TimelapseEditorScreen(
            archiveId: int.parse(q['archive']!),
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
            observers: [ModalObserver()],
            routes: [
              GoRoute(path: '/', builder: (_, _) => const DashboardScreen()),
            ],
          ),
          // Tab 1: Queue
          StatefulShellBranch(
            navigatorKey: _queueNavigatorKey,
            observers: [ModalObserver()],
            routes: [
              GoRoute(path: '/queue', builder: (_, _) => const QueueScreen()),
            ],
          ),
          // Tab 2: Archive
          StatefulShellBranch(
            navigatorKey: _archiveNavigatorKey,
            observers: [ModalObserver()],
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
            observers: [ModalObserver()],
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
            observers: [ModalObserver()],
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
  probe.watch(router);
  // "Change server" (profile set→null→set) rebuilds a new GoRouter — dispose
  // the old one so its listeners don't leak.
  ref.onDispose(() {
    probe.unwatch();
    router.dispose();
  });
  return router;
});
