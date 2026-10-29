import 'package:bambuddy_mobile/features/admin/api_keys_providers.dart';
import 'package:bambuddy_mobile/features/admin/groups_providers.dart';
import 'package:bambuddy_mobile/features/admin/users_providers.dart';
import 'package:bambuddy_mobile/features/archive/archive_providers.dart';
import 'package:bambuddy_mobile/features/dashboard/providers.dart';
import 'package:bambuddy_mobile/features/dashboard/smart_plugs_providers.dart';
import 'package:bambuddy_mobile/features/files/file_manager_providers.dart';
import 'package:bambuddy_mobile/features/finance/finance_providers.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_providers.dart';
import 'package:bambuddy_mobile/features/maintenance/maintenance_providers.dart';
import 'package:bambuddy_mobile/features/makerworld/makerworld_providers.dart';
import 'package:bambuddy_mobile/features/print_log/print_log_providers.dart';
import 'package:bambuddy_mobile/features/projects/projects_providers.dart';
import 'package:bambuddy_mobile/features/queue/queue_providers.dart';
import 'package:bambuddy_mobile/features/setup/providers.dart';
import 'package:bambuddy_mobile/features/stats/stats_providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The Riverpod 3 move once turned these into keep-alive providers: a screen's
  // state outlived the screen, and the dashboard and smart-plug polls never stopped.
  test('a screen\'s notifier provider disposes when nothing watches it', () {
    final Map<String, dynamic> screenProviders = {
      'apiKeysList': apiKeysListProvider,
      'groupsList': groupsListProvider,
      'usersList': usersListProvider,
      'archive': archiveProvider,
      'dashboard': dashboardProvider,
      'smartPlugs': smartPlugsProvider,
      'fileManager': fileManagerProvider,
      'financeTransactions': financeTransactionsProvider,
      'adminTransactions': adminTransactionsProvider,
      'inventory': inventoryProvider,
      'maintenanceOverview': maintenanceOverviewProvider,
      'maintenanceTypes': maintenanceTypesProvider,
      'makerworldResolve': makerworldResolveProvider,
      'printLog': printLogProvider,
      'projectsList': projectsListProvider,
      'queue': queueProvider,
      'queueSkipped': queueSkippedProvider,
      'setupController': setupControllerProvider,
      'stats': statsProvider,
      'failureAnalysis': failureAnalysisProvider,
    };
    for (final MapEntry(:key, :value) in screenProviders.entries) {
      expect(value.isAutoDispose, isTrue, reason: '$key is keep-alive');
    }
  });
}
