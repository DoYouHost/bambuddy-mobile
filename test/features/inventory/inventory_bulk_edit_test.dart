import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/core/models/inventory_bulk.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_providers.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_screen.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// The mass-edit sheet reached from multi-select. What matters here is what
/// leaves the phone: a blank field must stay out of the patch, because the
/// alternative — sending it — would blank that field on every selected spool.
class _FakeInventory extends InventoryNotifier {
  _FakeInventory({this.failure, this.outcome});

  /// Thrown instead of applying, to stand for a server that refuses.
  final AppApiException? failure;

  /// What the server reports back, when the test cares about the tally.
  final BulkOutcome? outcome;

  SpoolBulkPatch? patch;
  List<int>? ids;

  @override
  Future<InventoryState> build() async => InventoryState(
    spools: [
      const Spool(id: 1, material: 'PLA', brand: 'Bambu'),
      const Spool(id: 2, material: 'PETG', brand: 'Polymaker'),
    ],
  );

  @override
  Future<BulkOutcome> bulkUpdateSpools(
    Iterable<int> spoolIds,
    SpoolBulkPatch newPatch,
  ) async {
    if (failure case final f?) throw f;
    ids = spoolIds.toList();
    patch = newPatch;
    return outcome ?? BulkOutcome(ok: spoolIds.length);
  }
}

class _FixedBackend extends InventoryBackendNotifier {
  _FixedBackend(this._backend);

  final InventoryBackend _backend;

  @override
  InventoryBackend build() => _backend;
}

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('pl'));
  });

  /// Selects both spools and opens the mass-edit sheet from the overflow menu.
  Future<_FakeInventory> openSheet(
    WidgetTester tester, {
    AppApiException? failure,
    BulkOutcome? outcome,
    InventoryBackend backend = InventoryBackend.native,
  }) async {
    final fake = _FakeInventory(failure: failure, outcome: outcome);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inventoryProvider.overrideWith(() => fake),
          noServerProfileOverride,
          inventoryBackendProvider.overrideWith(() => _FixedBackend(backend)),
        ],
        child: plApp(const InventoryScreen()),
      ),
    );
    await settle(tester);

    await tester.longPress(find.text('Bambu PLA'));
    await settle(tester);
    await tester.tap(find.byIcon(Icons.select_all));
    await settle(tester);
    await tester.tap(find.byIcon(Icons.more_vert));
    await settle(tester);
    await tester.tap(find.text(l10n.inventoryBulkEdit));
    await settle(tester);
    // The sheet is a lazy ListView taller than the screen: Apply and the last
    // fields are not built until they scroll into range, and a finder cannot
    // tap what was never built.
    for (var i = 0; i < 4; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pump();
    }
    return fake;
  }

  Finder applyButton() =>
      find.widgetWithText(FilledButton, l10n.inventoryBulkEditApply(2));

  /// The note field is the plain text one — the combos are `DropdownMenu`s and
  /// carry their label differently.
  Finder noteField() => find.ancestor(
    of: find.text(l10n.inventoryFieldNote),
    matching: find.byType(TextFormField),
  );

  testWidgets('apply stays dead until a field is filled in', (tester) async {
    await openSheet(tester);

    expect(tester.widget<FilledButton>(applyButton()).onPressed, isNull);

    await tester.enterText(noteField(), 'restocked');
    await tester.pump();

    expect(tester.widget<FilledButton>(applyButton()).onPressed, isNotNull);
  });

  testWidgets('only the filled fields reach the patch', (tester) async {
    final fake = await openSheet(tester);

    await tester.enterText(noteField(), 'restocked');
    await tester.pump();
    await tester.tap(applyButton());
    await settle(tester);
    // The confirmation names both counts before anything is written.
    expect(find.text(l10n.inventoryBulkEditConfirmTitle(2)), findsOneWidget);
    await tester.tap(find.text(l10n.inventoryApply));
    await settle(tester);

    expect(fake.ids, [1, 2]);
    expect(fake.patch!.toNativeJson(), {'note': 'restocked'});
  });

  // The decimal key of a Polish keyboard. The field used to refuse it outright:
  // the validator called it "not a number" and the price never reached the
  // patch — a rejection the user could do nothing about, since the comma is
  // what the phone's own numeric layout puts there.
  testWidgets('a comma is the decimal point the keyboard offers', (
    tester,
  ) async {
    final fake = await openSheet(tester);

    await tester.enterText(
      find.ancestor(
        of: find.text(l10n.inventoryFieldCostPerKg),
        matching: find.byType(TextFormField),
      ),
      '89,50',
    );
    await tester.pump();
    await tester.tap(applyButton());
    await settle(tester);
    await tester.tap(find.text(l10n.inventoryApply));
    await settle(tester);

    expect(fake.patch!.toNativeJson(), {'cost_per_kg': 89.5});
  });

  testWidgets('a number that is not a number blocks the whole edit', (
    tester,
  ) async {
    // Without the validator the field would be dropped from the patch and the
    // tally would still report every spool as updated.
    final fake = await openSheet(tester);

    await tester.enterText(
      find.ancestor(
        of: find.text(l10n.inventoryFieldCostPerKg),
        matching: find.byType(TextFormField),
      ),
      'darmowa',
    );
    await tester.pump();
    await tester.tap(applyButton());
    await settle(tester);

    expect(find.text(l10n.inventoryFieldInvalidNumber), findsOneWidget);
    expect(fake.patch, isNull);
  });

  testWidgets('a value outside the range the server takes is refused here', (
    tester,
  ) async {
    // Clamping it silently would apply a threshold the user never chose, to
    // every spool in the selection.
    final fake = await openSheet(tester);

    await tester.enterText(
      find.ancestor(
        of: find.text(l10n.inventoryFieldLowStock),
        matching: find.byType(TextFormField),
      ),
      '150',
    );
    await tester.pump();
    await tester.tap(applyButton());
    await settle(tester);

    expect(find.text(l10n.inventoryFieldRange(1, 99)), findsOneWidget);
    expect(fake.patch, isNull);
  });

  testWidgets('a negative weight is refused, range or no range', (
    tester,
  ) async {
    // `core_weight` carries no `ge` constraint server-side, so a negative one is
    // stored as given and every remaining-weight sum built on it comes out
    // wrong — across the whole selection, silently.
    final fake = await openSheet(tester);

    await tester.enterText(
      find.ancestor(
        of: find.text(l10n.inventoryFieldEmptySpoolWeight),
        matching: find.byType(TextFormField),
      ),
      '-250',
    );
    await tester.pump();
    await tester.tap(applyButton());
    await settle(tester);

    expect(find.text(l10n.inventoryFieldNegative), findsOneWidget);
    expect(fake.patch, isNull);
  });

  testWidgets('Spoolman is not offered the fields it has no column for', (
    tester,
  ) async {
    await openSheet(tester, backend: InventoryBackend.spoolman);

    expect(find.text(l10n.inventoryFieldCategory), findsNothing);
    expect(find.text(l10n.inventoryFieldLowStock), findsNothing);
    // The fields it does take are still there.
    expect(find.text(l10n.inventoryFieldNote), findsOneWidget);
  });

  testWidgets('a mixed tally reports all three counts', (tester) async {
    await openSheet(
      tester,
      outcome: const BulkOutcome(ok: 1, skipped: 1, failed: 1),
    );

    await tester.enterText(noteField(), 'restocked');
    await tester.pump();
    await tester.tap(applyButton());
    await settle(tester);
    await tester.tap(find.text(l10n.inventoryApply));
    await settle(tester);

    expect(
      find.text(l10n.inventoryBulkPartialSkipped(1, 1, 1)),
      findsOneWidget,
    );
  });

  testWidgets('a refusal leaves the sheet open with the values typed', (
    tester,
  ) async {
    await openSheet(
      tester,
      failure: const AuthException(AppErrorCode.forbidden),
    );

    await tester.enterText(noteField(), 'restocked');
    await tester.pump();
    await tester.tap(applyButton());
    await settle(tester);
    await tester.tap(find.text(l10n.inventoryApply));
    await settle(tester);

    expect(applyButton(), findsOneWidget);
    expect(find.text('restocked'), findsOneWidget);
  });

  testWidgets('a server without the route says so instead of "not found"', (
    tester,
  ) async {
    await openSheet(
      tester,
      failure: const ApiException(AppErrorCode.badResponse, statusCode: 404),
    );

    await tester.enterText(noteField(), 'restocked');
    await tester.pump();
    await tester.tap(applyButton());
    await settle(tester);
    await tester.tap(find.text(l10n.inventoryApply));
    await settle(tester);

    expect(find.text(l10n.inventoryBulkEditUnsupported), findsOneWidget);
  });
}
