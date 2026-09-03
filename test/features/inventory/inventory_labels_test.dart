import 'dart:typed_data';

import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/core/models/spool_label.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/data/inventory_repository.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_providers.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_screen.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// Where on an Avery sheet the print starts.
///
/// The whole question exists because a sheet is usually part-used, and the
/// answer only reaches a server new enough to read it — an older one takes the
/// number, says nothing, and prints from position 1 onto labels that are no
/// longer there.
class _CapturingInventory extends InventoryNotifier {
  @override
  Future<InventoryState> build() async => InventoryState(spools: const [
        Spool(id: 1, material: 'PLA', brand: 'Bambu'),
      ]);
}

/// Records the render request, then refuses — the refusal is what keeps the
/// bytes away from the platform print dialog, which no widget test can serve.
class _CapturingRepository extends InventoryRepository {
  _CapturingRepository() : super(_UnusedSource());

  SpoolLabelTemplate? template;
  int? startingPosition;

  @override
  Future<Uint8List> renderLabels(
    List<int> spoolIds,
    SpoolLabelTemplate labelTemplate, {
    bool monochrome = false,
    int startingPosition = 1,
  }) async {
    template = labelTemplate;
    this.startingPosition = startingPosition;
    throw const ApiException(AppErrorCode.connectionError);
  }
}

/// Only [InventoryRepository.renderLabels] is exercised here; every other route
/// belongs to a screen this test never reaches.
class _UnusedSource implements SpoolInventorySource {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _NullProfile extends ServerProfileNotifier {
  @override
  ServerProfile? build() => null;
}

void main() {
  late AppLocalizations l10n;

  /// `pumpAndSettle` never returns on this screen — the search field's cursor
  /// blinks forever. A fixed span is long enough for a sheet to open.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 350));
    }
  }

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('pl'));
  });

  /// Opens the label sheet from the app bar and presses Print, which is what
  /// raises the stock picker.
  Future<_CapturingRepository> openTemplatePicker(
    WidgetTester tester, {
    required bool startingPositionSupported,
  }) async {
    final repo = _CapturingRepository();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        inventoryProvider.overrideWith(_CapturingInventory.new),
        serverProfileProvider.overrideWith(_NullProfile.new),
        inventoryRepositoryProvider.overrideWithValue(repo),
        labelStartingPositionProvider
            .overrideWith((ref) async => startingPositionSupported),
      ],
      child: plApp(const InventoryScreen()),
    ));
    await settle(tester);

    await tester.tap(find.byTooltip(l10n.inventoryLabelsPrintAll));
    await settle(tester);
    await tester.tap(find.text('${l10n.inventoryLabelsPrint} (1)'));
    await settle(tester);
    return repo;
  }

  /// Taps a stock card in the template sheet, scrolling it into range first:
  /// the sheet's list is lazy, and the two Avery entries sit below the fold.
  Future<void> pickTemplate(WidgetTester tester, String label) async {
    await tester.scrollUntilVisible(
      find.text(label),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text(label));
    await settle(tester);
  }

  testWidgets('an Avery sheet asks which slot to start at', (tester) async {
    final repo =
        await openTemplatePicker(tester, startingPositionSupported: true);
    await pickTemplate(tester, l10n.inventoryLabelsAveryL7160);

    expect(find.text(l10n.inventoryLabelsStartTitle), findsOneWidget);
    // One tappable slot per label on the sheet, and not one more: a position
    // past the sheet's capacity is a 422.
    expect(find.text('21'), findsOneWidget);
    expect(find.text('22'), findsNothing);

    // The grid is built in full but taller than the viewport, so the row the
    // sheet is meant to resume from has to be brought into range first.
    await tester.ensureVisible(find.text('7'));
    await settle(tester);
    await tester.tap(find.text('7'));
    await settle(tester);
    expect(repo.template, SpoolLabelTemplate.averyL7160);
    expect(repo.startingPosition, 7);
  });

  testWidgets('a roll template never asks — the server refuses any answer but 1',
      (tester) async {
    final repo =
        await openTemplatePicker(tester, startingPositionSupported: true);
    await pickTemplate(tester, l10n.inventoryLabelsBox40);

    expect(find.text(l10n.inventoryLabelsStartTitle), findsNothing);
    expect(repo.template, SpoolLabelTemplate.box40x30);
    expect(repo.startingPosition, 1);
  });

  testWidgets('a server that would ignore the answer is not asked either',
      (tester) async {
    // `LabelRequest` forbids no extra fields, so the sheet would print from 1
    // whatever was picked. Asking would cost a sheet of Avery stock to find out.
    final repo =
        await openTemplatePicker(tester, startingPositionSupported: false);
    await pickTemplate(tester, l10n.inventoryLabelsAveryL7160);

    expect(find.text(l10n.inventoryLabelsStartTitle), findsNothing);
    expect(repo.startingPosition, 1);
  });
}
