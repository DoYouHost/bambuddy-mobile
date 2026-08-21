import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_providers.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_screen.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// The spool tile's meta line, where the AMS slot label was being clipped to
/// "AMS0 ·…".
///
/// The cause was a `Spacer` between the weight text and the label: both are flex
/// children, so whatever space the fixed weight text left over was split evenly
/// between the label and an empty gap — the label could use only half of it no
/// matter how wide the row was. A tile is unreadable when it says which printer
/// holds the spool but not which slot, so this measures the rendered label
/// against the width its own text needs.
class _Shelf extends InventoryNotifier {
  _Shelf(this._spool, this._assignment);

  final Spool _spool;
  final SpoolAssignment _assignment;

  @override
  Future<InventoryState> build() async => InventoryState(
        spools: [_spool],
        assignmentBySpool: {_spool.id: _assignment},
      );
}

class _NullProfile extends ServerProfileNotifier {
  @override
  ServerProfile? build() => null;
}

void main() {
  /// Width the text would take unconstrained — anything narrower on screen
  /// means the ellipsis ate part of it.
  double intrinsicWidth(Text text) {
    final painter = TextPainter(
      text: TextSpan(text: text.data, style: text.style),
      textDirection: TextDirection.ltr,
    )..layout();
    return painter.width;
  }

  Future<void> pumpShelf(
    WidgetTester tester, {
    required Size surface,
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // A four-digit label weight and a three-digit remainder: the longest the
    // weight half realistically gets, which is when the row is tightest.
    const spool = Spool(
      id: 128,
      material: 'PETG',
      brand: 'Polymaker',
      subtype: 'Translucent',
      labelWeight: 1000,
      weightUsed: 340,
    );
    const assignment = SpoolAssignment(
      spoolId: 128,
      printerId: 1,
      amsId: 0,
      trayId: 0,
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        inventoryProvider.overrideWith(() => _Shelf(spool, assignment)),
        serverProfileProvider.overrideWith(_NullProfile.new),
      ],
      child: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: plApp(const InventoryScreen()),
      ),
    ));
    // Not pumpAndSettle: the search field's cursor blinks forever, so no frame
    // ever has nothing animating.
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 350));
    }
  }

  /// The slot label as [assignmentSlotLabel] builds it for AMS unit 0, tray 0.
  final slotLabel = find.text('AMS0 · 1');

  testWidgets('the AMS slot label is not clipped on a 360 dp phone',
      (tester) async {
    await pumpShelf(tester, surface: const Size(360, 640));

    expect(slotLabel, findsOneWidget);
    expect(
      tester.getSize(slotLabel).width,
      greaterThanOrEqualTo(intrinsicWidth(tester.widget<Text>(slotLabel))),
      reason: 'the slot is the half of the row worth keeping whole',
    );
  });

  testWidgets('nor at the largest system text size', (tester) async {
    // The weight half has to give way here, and it can: it ends in the label
    // weight, which the progress bar above already shows.
    await pumpShelf(tester, surface: const Size(360, 640), textScale: 1.3);

    expect(
      tester.getSize(slotLabel).width,
      greaterThanOrEqualTo(intrinsicWidth(tester.widget<Text>(slotLabel))),
    );
    expect(tester.takeException(), isNull, reason: 'and nothing overflows');
  });
}
