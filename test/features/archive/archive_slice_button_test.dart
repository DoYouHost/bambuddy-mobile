import 'dart:async';

import 'package:bambuddy_mobile/core/models/archive.dart';
import 'package:bambuddy_mobile/core/models/archive_capabilities.dart';
import 'package:bambuddy_mobile/core/models/no_3mf_warning.dart';
import 'package:bambuddy_mobile/features/archive/archive_providers.dart';
import 'package:bambuddy_mobile/features/archive/archive_screen.dart';
import 'package:bambuddy_mobile/features/pipelines/pipelines_providers.dart';
import 'package:bambuddy_mobile/features/slicer/slice_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

/// The two answers behind the archive's slice button, and the different things
/// they do: the server-wide sidecar flag hides the section, while "this print
/// cannot be re-sliced" only disables it and says why.
///
/// Nothing else in the suite opens this sheet — see the weight row's own test.
void main() {
  const archive = Archive(
    id: 1,
    filename: 'benchy.gcode.3mf',
    status: 'completed',
    printName: 'Benchy',
  );

  /// Opens the print's sheet, which is where the button lives.
  var capabilityReads = 0;

  Future<void> openSheet(
    WidgetTester tester, {
    required AsyncValue<bool> sidecar,
    Completer<ArchiveCapabilities>? capabilities,
    bool sliceable = true,
    bool failing = false,
  }) async {
    capabilityReads = 0;
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await pumpPhone(
      tester,
      const ArchiveScreen(),
      overrides: [
        archiveListOverride([archive]),
        no3mfWarningProvider.overrideWith((ref) async => No3mfWarning.none),
        sharedPreferencesProvider.overrideWithValue(prefs),
        noServerProfileOverride,
        slicerEnabledProvider.overrideWithValue(sidecar),
        // Its own routes are a separate question; this keeps the second button
        // out of the way.
        canRunPipelinesProvider.overrideWith((ref) async => false),
        archiveCapabilitiesProvider(archive.id).overrideWith((ref) {
          capabilityReads++;
          if (failing) throw StateError('capabilities unreachable');
          return capabilities?.future ??
              Future.value(
                ArchiveCapabilities(hasSource: sliceable, hasGcode: true),
              );
        }),
      ],
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Benchy'));
    await tester.pumpAndSettle();
  }

  Finder sliceButton() =>
      find.widgetWithText(OutlinedButton, 'Potnij').hitTestable();

  bool enabled(WidgetTester tester) =>
      tester.widget<OutlinedButton>(sliceButton()).onPressed != null;

  testWidgets('a print that can be re-sliced offers the button', (
    tester,
  ) async {
    await openSheet(tester, sidecar: const AsyncValue.data(true));

    expect(sliceButton(), findsOneWidget);
    expect(enabled(tester), isTrue);
    expect(find.textContaining('nie da się go pociąć'), findsNothing);
  });

  testWidgets('a print that cannot stays on screen, disabled, with a reason', (
    tester,
  ) async {
    // The point of this shape: showing the button and collapsing the row a
    // moment later is a flicker the user has to interpret.
    await openSheet(
      tester,
      sidecar: const AsyncValue.data(true),
      sliceable: false,
    );

    expect(sliceButton(), findsOneWidget);
    expect(enabled(tester), isFalse);
    expect(find.textContaining('nie da się go pociąć'), findsOneWidget);
  });

  testWidgets('a server with no slicer draws none of it, and is not asked', (
    tester,
  ) async {
    // Not a disabled button: the feature does not exist on this server, so
    // advertising it on every entry would be noise. And asking what this entry
    // can do is a request of its own — one such a server must never receive.
    await openSheet(tester, sidecar: const AsyncValue.data(false));

    expect(sliceButton(), findsNothing);
    expect(find.textContaining('nie da się go pociąć'), findsNothing);
    expect(capabilityReads, 0);
  });

  testWidgets('an unsettled sidecar flag holds the second question back', (
    tester,
  ) async {
    // The early return covers a server that said no. This covers the moment
    // before it has said anything: sending the per-entry request then would be
    // asking on a guess, and the answer is thrown away if the flag comes back
    // false.
    await openSheet(tester, sidecar: const AsyncValue<bool>.loading());

    expect(sliceButton(), findsOneWidget);
    expect(enabled(tester), isFalse);
    expect(capabilityReads, 0);
  });

  testWidgets('a read that failed is explained, not silently dead', (
    tester,
  ) async {
    // The rule the disabled state is held to: a control that stays greyed owes
    // the user a line saying why. Without one this is a button that does
    // nothing, for ever, with no way to tell what went wrong.
    await openSheet(
      tester,
      sidecar: const AsyncValue.data(true),
      failing: true,
    );

    expect(sliceButton(), findsOneWidget);
    expect(enabled(tester), isFalse);
    expect(find.text('Nie udało się połączyć z serwerem'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('while the answer is on its way it is disabled and silent', (
    tester,
  ) async {
    // No reason yet to give, and a note that appeared and left would be the
    // flicker moved one row down.
    final held = Completer<ArchiveCapabilities>();
    await openSheet(
      tester,
      sidecar: const AsyncValue.data(true),
      capabilities: held,
    );

    expect(sliceButton(), findsOneWidget);
    expect(enabled(tester), isFalse);
    expect(find.textContaining('nie da się go pociąć'), findsNothing);

    held.complete(const ArchiveCapabilities(hasSource: true));
    await tester.pumpAndSettle();
    expect(enabled(tester), isTrue, reason: 'it enables itself on the answer');
  });
}
