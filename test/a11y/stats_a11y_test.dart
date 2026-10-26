import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/archive_stats.dart';
import 'package:bambuddy_mobile/core/models/failure_analysis.dart';
import 'package:bambuddy_mobile/core/models/inventory.dart'
    show MaterialNumberStats;
import 'package:bambuddy_mobile/core/models/supplier.dart';
import 'package:bambuddy_mobile/features/stats/stats_common.dart';
import 'package:bambuddy_mobile/features/stats/stats_providers.dart';
import 'package:bambuddy_mobile/features/stats/statistics_screen.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers.dart';
import 'a11y_harness.dart';

/// Rendered contrast and touch targets for `lib/features/stats/`: the screen on
/// the demo backend (every card, scrolled through), both app-bar menus, the
/// custom date-range dialog, an empty archive, a failed load, the failure
/// card without failures and with a failed read, the supplier and material
/// number cards (filled and failed; the demo seeds neither) and each card
/// that has a Weight / Prints / Time toggle switched to the other two metrics.
/// A lazy list drops the state of a card scrolled far out of view, so each
/// toggle is switched at its own scroll position and measured there. Not
/// covered: the print log screen behind the failure card's shortcut, which has
/// its own file.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The stats requests carry the device's time zone, asked over this channel.
  // Unanswered, the reply arrives on the real event loop and the failure
  // card's second request starts after the test has already ended.
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('page.codeberg.morganmlgman.bambuddy/clock'),
          (call) async => null,
        );
  });

  a11ySurface(
    'statistics',
    home: () => const StatisticsScreen(),
    overrides: _quiet,
    shows: find.text(pl.statsOverview),
  );

  a11ySurface(
    'statistics, user filter menu',
    home: () => const StatisticsScreen(),
    overrides: _quiet,
    arrange: (tester) async {
      await tester.tap(byLogId('stats.user_filter'));
    },
    shows: byLogId('stats.user_filter.all'),
  );

  a11ySurface(
    'statistics, range menu',
    home: () => const StatisticsScreen(),
    overrides: _quiet,
    arrange: (tester) async {
      await tester.tap(byLogId('stats.range'));
    },
    shows: byLogId('stats.range.last7Days'),
  );

  a11ySurface(
    'statistics, custom range dialog',
    home: () => const StatisticsScreen(),
    overrides: _quiet,
    arrange: (tester) async {
      await tester.tap(byLogId('stats.range'));
      await a11ySettle(tester, const Duration(milliseconds: 500));
      await tester.tap(byLogId('stats.range.custom'));
    },
    shows: find.byType(Dialog),
  );

  a11ySurface(
    'statistics, last seven days',
    home: () => const StatisticsScreen(),
    overrides: [
      ..._quiet,
      statsFilterProvider.overrideWith(
        () => _FixedFilter(const StatsFilter(range: StatsRange.last7Days)),
      ),
    ],
    shows: find.text(pl.statsOverview),
  );

  a11ySurface(
    'statistics, empty archive',
    demo: false,
    home: () => const StatisticsScreen(),
    overrides: [
      fakeServerProfileOverride(),
      statsUsersProvider.overrideWith((ref) async => _users),
      statsProvider.overrideWith(_EmptyStats.new),
    ],
    shows: find.text(pl.statsEmpty),
  );

  a11ySurface(
    'statistics, load failed',
    demo: false,
    home: () => const StatisticsScreen(),
    overrides: [
      fakeServerProfileOverride(),
      statsUsersProvider.overrideWith((ref) async => _users),
      statsProvider.overrideWith(_FailedStats.new),
    ],
    shows: find.text(pl.retry),
  );

  a11ySurface(
    'statistics, no failures and stock cards filled',
    home: () => const StatisticsScreen(),
    overrides: [
      ..._quiet,
      failureAnalysisProvider.overrideWith(_NoFailures.new),
      supplierStatsProvider.overrideWith((ref) async => _suppliers),
      materialNumberStatsProvider.overrideWith((ref) async => _numbers),
    ],
    shows: find.text(pl.statsNoFailures),
  );

  a11ySurface(
    'statistics, failure analysis and stock cards failed',
    home: () => const StatisticsScreen(),
    overrides: [
      ..._quiet,
      failureAnalysisProvider.overrideWith(_FailedFailures.new),
      supplierStatsProvider.overrideWith((ref) async => throw _refusal),
      materialNumberStatsProvider.overrideWith((ref) async => throw _refusal),
    ],
    shows: find.text(pl.statsBySupplierFailed),
  );

  for (final (card, titleOf) in [
    ('printer card', (() => pl.statsByPrinter)),
    ('material card', (() => pl.statsByMaterialTitle)),
    ('habits card', (() => pl.statsPrintHabits)),
  ]) {
    for (final (metric, labelOf) in [
      ('prints', (() => pl.statsMetricPrints)),
      ('time', (() => pl.statsMetricTime)),
    ]) {
      a11ySurface(
        'statistics, $card by $metric',
        home: () => const StatisticsScreen(),
        overrides: _quiet,
        arrange: (tester) async {
          await tester.scrollUntilVisible(
            find.text(titleOf()),
            400,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pump();
          await tester.tap(_toggleOf(titleOf(), labelOf()));
        },
        shows: find.text(titleOf()),
      );
    }
  }
}

/// A segment of the toggle in the card titled [title].
Finder _toggleOf(String title, String label) => find.descendant(
  of: find.ancestor(of: find.text(title), matching: find.byType(SectionCard)),
  matching: find.text(label),
);

/// The printer names the by-printer card reads. The demo would answer them,
/// but only once the card is built, which a scroll does on the last page: the
/// request is then still in flight when the test ends.
final _quiet = [
  livePrinterNamesProvider.overrideWith(
    (ref) async => const {1: 'X1 Carbon', 2: 'P1S', 3: 'A1 mini'},
  ),
];

// Not an `AppApiException`, so the card words the failure itself.
final _refusal = StateError('refused');

const _users = [UserSummary(id: 1, username: 'demo')];

const _suppliers = [
  SupplierStats(
    supplierId: 1,
    supplierName: 'Filament shop',
    spoolCount: 6,
    remainingGrams: 3100,
    consumedGrams: 2400,
    cost: 119.5,
  ),
  SupplierStats(
    supplierId: 2,
    supplierName: 'Local maker',
    spoolCount: 2,
    remainingGrams: 800,
    consumedGrams: 600,
    cost: 31,
  ),
];

const _numbers = [
  MaterialNumberStats(
    materialNumber: '10101',
    spoolCount: 3,
    remainingGrams: 1900,
    consumedGrams: 1200,
    cost: 52,
  ),
  MaterialNumberStats(
    materialNumber: '10600',
    spoolCount: 1,
    remainingGrams: 450,
    consumedGrams: 550,
    cost: 18.4,
  ),
];

class _FixedFilter extends StatsFilterNotifier {
  _FixedFilter(this.filter);

  final StatsFilter filter;

  @override
  StatsFilter build() => filter;
}

class _EmptyStats extends StatsNotifier {
  @override
  Future<ArchiveStats> build() async => const ArchiveStats();
}

class _FailedStats extends StatsNotifier {
  @override
  Future<ArchiveStats> build() async =>
      throw const ApiException(AppErrorCode.serverUnreachable);
}

class _NoFailures extends FailureAnalysisNotifier {
  @override
  Future<FailureAnalysis> build() async =>
      const FailureAnalysis(totalPrints: 40, periodDays: 30);
}

class _FailedFailures extends FailureAnalysisNotifier {
  @override
  Future<FailureAnalysis> build() async => throw _refusal;
}
