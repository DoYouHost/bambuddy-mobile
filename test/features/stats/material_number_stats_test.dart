import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:bambuddy_mobile/features/stats/stats_providers.dart';
import 'package:bambuddy_mobile/features/stats/stats_sections.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

const _rows = [
  MaterialNumberStats(
    materialNumber: '15',
    spoolCount: 2,
    remainingGrams: 1500,
    consumedGrams: 820,
    cost: 19.4,
  ),
  MaterialNumberStats(materialNumber: 'A-104', spoolCount: 1),
];

void main() {
  group('materialNumberStatsProvider', () {
    Future<List<MaterialNumberStats>> read({
      required bool supported,
      InventoryBackend backend = InventoryBackend.native,
    }) async {
      final container = ProviderContainer(
        overrides: [
          noServerProfileOverride,
          inventoryRepositoryOf(backend),
          materialNumberSupportedProvider.overrideWithValue(
            AsyncData(supported),
          ),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(materialNumberStatsProvider, (_, _) {});
      addTearDown(sub.close);
      return container.read(materialNumberStatsProvider.future);
    }

    test('never asks a server without the number', () async {
      expect(await read(supported: false), isEmpty);
    });

    test('never asks in Spoolman mode, where the aggregate is empty', () async {
      expect(
        await read(supported: true, backend: InventoryBackend.spoolman),
        isEmpty,
      );
    });
  });

  group('MaterialNumberStatsCard', () {
    late AppLocalizations l10n;

    setUpAll(() async {
      l10n = await AppLocalizations.delegate.load(const Locale('pl'));
    });

    Future<void> pumpCard(WidgetTester tester, Override stats) => pumpPhone(
      tester,
      const Scaffold(
        body: SingleChildScrollView(child: MaterialNumberStatsCard()),
      ),
      overrides: [noServerProfileOverride, stats],
    ).then((_) => settle(tester));

    testWidgets('one bar per number, stock and spend under it', (tester) async {
      await pumpCard(
        tester,
        materialNumberStatsProvider.overrideWith((_) async => _rows),
      );

      expect(find.text(l10n.statsByMaterialNumber), findsOneWidget);
      expect(find.text('15'), findsOneWidget);
      expect(find.text('820 g'), findsOneWidget);
      expect(
        find.text(
          l10n.statsSupplierDetail(
            l10n.inventorySpoolCount(2),
            '1.50 kg',
            '19.40',
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('A-104'), findsOneWidget);
    });

    testWidgets('nothing at all when no spool carries a number', (
      tester,
    ) async {
      await pumpCard(
        tester,
        materialNumberStatsProvider.overrideWith((_) async => const []),
      );
      expect(find.text(l10n.statsByMaterialNumber), findsNothing);
    });

    testWidgets('a failed read says so instead of passing for empty', (
      tester,
    ) async {
      await pumpCard(
        tester,
        materialNumberStatsProvider.overrideWith(
          (_) => throw const ApiException(
            AppErrorCode.badResponse,
            statusCode: 500,
          ),
        ),
      );
      expect(find.text(l10n.statsByMaterialNumberFailed), findsOneWidget);
    });
  });
}
