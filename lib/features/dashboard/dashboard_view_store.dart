import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import 'dashboard_filters.dart';
import 'dashboard_sort.dart';

/// What the dashboard remembers between visits: the filters, the sort and which
/// sections are folded. The web keeps all of it in `localStorage`
/// (`PrintersPage.tsx`, #2833).
///
/// **The keys and the names inside are persisted values.**
class DashboardView {
  const DashboardView({
    this.filters = const DashboardFilters(),
    this.sort = const DashboardSort(),
    this.collapsed = const {},
  });

  /// Reads what [toJson] wrote. Every value is validated: one the app no
  /// longer offers would filter every printer out with nothing to explain why
  /// (the web validates the status for the same reason).
  factory DashboardView.fromJson(Map<String, dynamic> json) {
    T? named<T extends Enum>(List<T> values, Object? name) =>
        values.where((v) => v.name == name).firstOrNull;
    final location = json['location'];
    return DashboardView(
      filters: DashboardFilters(
        status:
            named(PrinterStatusBucket.values, json['status']) ??
            PrinterStatusBucket.all,
        hideOffline: json['hide_offline'] == true,
        location: location is String && location.isNotEmpty ? location : null,
      ),
      sort: DashboardSort(
        by: named(PrinterSort.values, json['sort']) ?? PrinterSort.name,
        ascending: json['ascending'] != false,
      ),
      collapsed: {
        if (json['collapsed'] case final List<dynamic> keys)
          for (final k in keys)
            if (k is String) k,
      },
    );
  }

  final DashboardFilters filters;
  final DashboardSort sort;
  final Set<String> collapsed;

  Map<String, dynamic> toJson() => {
    'status': filters.status.name,
    'hide_offline': filters.hideOffline,
    'location': filters.location,
    'sort': sort.by.name,
    'ascending': sort.ascending,
    'collapsed': collapsed.toList(),
  };
}

/// The remembered view as it was when the dashboard opened.
final dashboardViewStoreProvider = Provider.autoDispose<DashboardView>(
  (ref) => DashboardView.fromJson(
    ref.watch(settingsRepositoryProvider).loadDashboardView(),
  ),
);

/// Writes the view back whenever one of its three parts changes. Watched by
/// the dashboard, so it lives exactly as long as the screen that changes them.
final dashboardViewPersistenceProvider = Provider.autoDispose<void>((ref) {
  void save() {
    ref
        .read(settingsRepositoryProvider)
        .saveDashboardView(
          DashboardView(
            filters: ref.read(dashboardFiltersProvider),
            sort: ref.read(dashboardSortProvider),
            collapsed: ref.read(dashboardCollapsedGroupsProvider),
          ).toJson(),
        );
  }

  ref
    ..listen(dashboardFiltersProvider, (_, _) => save())
    ..listen(dashboardSortProvider, (_, _) => save())
    ..listen(dashboardCollapsedGroupsProvider, (_, _) => save());
});
