import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/core/models/inventory_bulk.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
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
  _FakeInventory({this.failure});

  /// Thrown instead of applying, to stand for a server that refuses.
  final AppApiException? failure;

  SpoolBulkPatch? patch;
  List<int>? ids;

  @override
  Future<InventoryState> build() async => InventoryState(spools: [
        const Spool(id: 1, material: 'PLA', brand: 'Bambu'),
        const Spool(id: 2, material: 'PETG', brand: 'Polymaker'),
      ]);

  @override
  Future<BulkOutcome> bulkUpdateSpools(
    Iterable<int> spoolIds,
    SpoolBulkPatch newPatch,
  ) async {
    if (failure case final f?) throw f;
    ids = spoolIds.toList();
    patch = newPatch;
    return BulkOutcome(ok: spoolIds.length);
  }
}

/// Null profile: nothing here talks to a server, and building the API client
/// without one throws by design.
class _NullProfile extends ServerProfileNotifier {
  @override
  ServerProfile? build() => null;
}

void main() {
  late AppLocalizations l10n;

  /// `pumpAndSettle` never returns on this screen: the search field's cursor
  /// blinks forever, so there is no frame where nothing is animating. Pumping a
  /// fixed span is long enough for a sheet or a dialog to finish opening.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 350));
    }
  }

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('pl'));
  });

  /// Selects both spools and opens the mass-edit sheet from the overflow menu.
  Future<_FakeInventory> openSheet(
    WidgetTester tester, {
    AppApiException? failure,
  }) async {
    final fake = _FakeInventory(failure: failure);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        inventoryProvider.overrideWith(() => fake),
        serverProfileProvider.overrideWith(_NullProfile.new),
      ],
      child: plApp(const InventoryScreen()),
    ));
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

  Finder applyButton() => find.widgetWithText(
        FilledButton,
        l10n.inventoryBulkEditApply(2),
      );

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

  testWidgets('a number that is not a number blocks the whole edit',
      (tester) async {
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

  testWidgets('a refusal leaves the sheet open with the values typed',
      (tester) async {
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

  testWidgets('a server without the route says so instead of "not found"',
      (tester) async {
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
