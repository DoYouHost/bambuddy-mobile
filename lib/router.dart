import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/dashboard/dashboard_screen.dart';
import 'features/setup/setup_screen.dart';
import 'providers.dart';

/// Płaskie trasy v1 (docelowo dojdą /printer/:id, /queue, /archive,
/// /settings). Router jest odtwarzany przy zmianie istnienia profilu —
/// przy dwóch trasach utrata stosu nawigacji nie boli.
final routerProvider = Provider<GoRouter>((ref) {
  final hasProfile =
      ref.watch(serverProfileProvider.select((p) => p != null));
  return GoRouter(
    initialLocation: hasProfile ? '/' : '/setup',
    redirect: (context, state) {
      if (!hasProfile && state.matchedLocation != '/setup') {
        return '/setup';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/setup', builder: (_, _) => const SetupScreen()),
      GoRoute(path: '/', builder: (_, _) => const DashboardScreen()),
    ],
  );
});
