import 'package:bambuddy_mobile/core/models/calibration_option.dart';
import 'package:bambuddy_mobile/core/models/plate_list.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:bambuddy_mobile/core/settings/print_options.dart';
import 'package:bambuddy_mobile/features/queue/queue_edit_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'queue_form_harness.dart';

/// Three plates, as a 3MF sliced for a plate farm answers.
PlateList _threePlates() => PlateList.fromJson({
  'plates': [
    for (var i = 1; i <= 3; i++)
      {
        'index': i,
        'name': 'Plate $i',
        'object_count': i,
        'has_thumbnail': false,
      },
  ],
  'is_multi_plate': true,
  'has_gcode': true,
});

/// How the plate row spells plate [index] of [_threePlates].
String _plate(int index) => formL10n.queueEditPlateNamed(index, 'Plate $index');

/// The state the form is in after the user has been through the mapping sheet:
/// slots picked for the plate that was selected *then*.
const _mapped = QueueItem(
  id: 0,
  position: 0,
  status: 'pending',
  archiveId: 77,
  archiveName: 'cube.3mf',
  printerId: 1,
  slicedForModel: 'X2D',
  plateId: 1,
  amsMapping: [2, 0],
);

void main() {
  setUp(setUpQueueForm);

  testWidgets('reprint: ASAP sends insert_at_top and does not stage the item', (
    tester,
  ) async {
    await tester.pumpWidget(queueFormScreen(archiveDraft()));
    await tester.pumpAndSettle();

    await submitQueueForm(tester);

    expect(capturedBody?['archive_id'], 77);
    expect(capturedBody?['printer_id'], 1);
    expect(capturedBody?['insert_at_top'], true);
    expect(capturedBody?['manual_start'], false);
    expect(capturedBody?.containsKey('scheduled_time'), isFalse);
  });

  // The gap this closes: the server starts a job on `plate_id or 1`, so a
  // reprint that drops the archive's plate prints plate 1 of a multi-plate file
  // instead of the plate the archive is a record of.
  testWidgets('reprint of a multi-plate archive sends the plate it ran on', (
    tester,
  ) async {
    await tester.pumpWidget(
      queueFormScreen(archiveDraft(plateId: 3), plates: _threePlates()),
    );
    await tester.pumpAndSettle();

    expect(find.text(_plate(3)), findsOneWidget);

    await submitQueueForm(tester);

    expect(capturedBody?['plate_id'], 3);
  });

  testWidgets('a single-plate file is offered no plate to choose', (
    tester,
  ) async {
    await tester.pumpWidget(queueFormScreen(archiveDraft()));
    await tester.pumpAndSettle();

    expect(find.text(formL10n.queueEditPlate), findsNothing);

    await submitQueueForm(tester);

    // Absent, not null: the server's own default has to stay in charge for
    // every install that never reported a plate.
    expect(capturedBody?.containsKey('plate_id'), isFalse);
  });

  testWidgets('picking another plate sends that one and drops the mapping', (
    tester,
  ) async {
    await tester.pumpWidget(queueFormScreen(_mapped, plates: _threePlates()));
    await tester.pumpAndSettle();

    await tester.tap(find.text(_plate(1)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_plate(2)).last);
    await tester.pumpAndSettle();

    expect(find.text(_plate(2)), findsOneWidget);

    await submitQueueForm(tester);

    expect(capturedBody?['plate_id'], 2);
    // The mapping it was pre-filled with belongs to another plate's slots, so
    // it must not ride along — an absent mapping is the server auto-matching.
    expect(capturedBody?.containsKey('ams_mapping'), isFalse);
  });

  // Guards the test above: without a plate change the same form does send the
  // mapping, so its absence there is the reset and not just an empty form.
  testWidgets('an untouched plate keeps the mapping it was opened with', (
    tester,
  ) async {
    await tester.pumpWidget(queueFormScreen(_mapped, plates: _threePlates()));
    await tester.pumpAndSettle();

    await submitQueueForm(tester);

    expect(capturedBody?['ams_mapping'], [2, 0]);
    expect(capturedBody?['plate_id'], 1);
  });

  testWidgets('add to queue: the item is created staged and does not jump', (
    tester,
  ) async {
    await tester.pumpWidget(
      queueFormScreen(
        archiveDraft(manualStart: true),
        schedule: QueueScheduleType.queue,
      ),
    );
    await tester.pumpAndSettle();

    await submitQueueForm(tester);

    // Staged from the first moment: the scheduler will not take it until the
    // user starts it by hand — that is what closes the 06b race.
    expect(capturedBody?['manual_start'], true);
    expect(capturedBody?.containsKey('insert_at_top'), isFalse);
  });

  testWidgets('a first print: everything on except the timelapse', (
    tester,
  ) async {
    await tester.pumpWidget(queueFormScreen(archiveDraft()));
    await tester.pumpAndSettle();

    await submitQueueForm(tester);

    expect(capturedBody?['bed_levelling'], true);
    expect(capturedBody?['flow_cali'], true);
    expect(capturedBody?['vibration_cali'], true);
    expect(capturedBody?['layer_inspect'], true);
    expect(capturedBody?['timelapse'], false);
    // Offered on dual-nozzle models only — the draft is sliced_for_model X2D.
    expect(capturedBody?['nozzle_offset_cali'], true);
  });

  testWidgets('the next print starts from the options last used', (
    tester,
  ) async {
    await queueFormPrefs.setString(
      'print_options',
      const PrintOptions(
        bedLevelling: CalibrationOption.off,
        flowCali: CalibrationOption.off,
        vibrationCali: true,
        layerInspect: false,
        timelapse: true,
        nozzleOffsetCali: CalibrationOption.on,
      ).encode(),
    );

    await tester.pumpWidget(queueFormScreen(archiveDraft()));
    await tester.pumpAndSettle();
    await submitQueueForm(tester);

    expect(capturedBody?['bed_levelling'], false);
    expect(capturedBody?['flow_cali'], false);
    expect(capturedBody?['timelapse'], true);
  });

  testWidgets('a successful create remembers the toggles', (tester) async {
    await tester.pumpWidget(queueFormScreen(archiveDraft()));
    await tester.pumpAndSettle();

    // The first switch is bed levelling (on by default).
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    await submitQueueForm(tester);

    expect(storedPrintOptions().bedLevelling, CalibrationOption.off);
    expect(storedPrintOptions().vibrationCali, true);
  });

  testWidgets('editing an item leaves the remembered options alone', (
    tester,
  ) async {
    // A change made on one item is about THAT item — otherwise a one-off
    // exception would follow the user into every print after it.
    await tester.pumpWidget(
      queueFormScreen(
        QueueItem.fromJson({
          'id': 5,
          'position': 1,
          'status': 'pending',
          'archive_id': 77,
          'printer_id': 1,
        }),
        schedule: QueueScheduleType.queue,
        mode: QueueEditMode.edit,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    await submitQueueForm(tester, edit: true);

    expect(storedPrintOptions(), PrintOptions.initial);
  });

  testWidgets('the print options on the form ride along with the POST', (
    tester,
  ) async {
    await tester.pumpWidget(queueFormScreen(archiveDraft()));
    await tester.pumpAndSettle();

    // The first switch in the options section is bed levelling (on by default).
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    await submitQueueForm(tester);

    expect(capturedBody?['bed_levelling'], false);
    expect(capturedBody?['vibration_cali'], true);
    expect(capturedBody?['preheat_override'], 'inherit');
  });

  testWidgets('the filled action fits the bar at a large text size', (
    tester,
  ) async {
    // The pill in the app bar has 56 px of height to work with — at a larger
    // text size it grows, so an overflow would stay silent until the first
    // report.
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(queueFormScreen(archiveDraft()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.widgetWithText(FilledButton, formL10n.queueCreateSubmit),
      findsOneWidget,
    );
  });

  testWidgets('with no printer chosen nothing reaches the server', (
    tester,
  ) async {
    await tester.pumpWidget(queueFormScreen(archiveDraft(printerId: null)));
    await tester.pumpAndSettle();

    await submitQueueForm(tester);

    expect(capturedBody, isNull);
    expect(find.text(formL10n.queueEditNoPrinter), findsOneWidget);
  });

  group('auto-print G-code injection', () {
    final label = formL10n.queueEditGcodeInjection;

    /// The flags sit at the bottom of a long form, so they must be scrolled to
    /// before a finder can see them at all — "Power off" is the last row that is
    /// always there, which makes it the anchor.
    Future<void> revealFlags(WidgetTester tester) async {
      await tester.dragUntilVisible(
        find.text(formL10n.queueEditPowerOff),
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
    }

    Future<void> tapInjection(WidgetTester tester) async {
      await revealFlags(tester);
      await tester.ensureVisible(find.text(label));
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    /// The options blob a plate-swap user ends up with: injection remembered ON.
    Future<void> rememberInjection() => queueFormPrefs.setString(
      'print_options',
      const PrintOptions(
        bedLevelling: CalibrationOption.on,
        flowCali: CalibrationOption.on,
        vibrationCali: true,
        layerInspect: true,
        timelapse: false,
        nozzleOffsetCali: CalibrationOption.on,
        gcodeInjection: true,
      ).encode(),
    );

    testWidgets('a server with no snippets does not offer the option', (
      tester,
    ) async {
      await tester.pumpWidget(queueFormScreen(archiveDraft()));
      await tester.pumpAndSettle();
      await revealFlags(tester);

      expect(find.text(label), findsNothing);

      await submitQueueForm(tester);

      expect(
        capturedBody?.containsKey('gcode_injection'),
        isFalse,
        reason: 'without snippets the flag is inert anyway',
      );
    });

    testWidgets('the ticked option rides with the POST', (tester) async {
      await tester.pumpWidget(
        queueFormScreen(archiveDraft(), snippets: {'X2D'}),
      );
      await tester.pumpAndSettle();

      await tapInjection(tester);
      await submitQueueForm(tester);

      expect(capturedBody?['gcode_injection'], true);
      expect(
        storedPrintOptions().gcodeInjection,
        isTrue,
        reason: 'a plate-swap rig needs this on every print',
      );
    });

    testWidgets('a remembered option starts ticked', (tester) async {
      await rememberInjection();

      await tester.pumpWidget(
        queueFormScreen(archiveDraft(), snippets: {'X2D'}),
      );
      await tester.pumpAndSettle();
      await submitQueueForm(tester);

      expect(capturedBody?['gcode_injection'], true);
    });

    testWidgets(
      'a remembered option does not reach a server with no snippets',
      (tester) async {
        // Server without snippets: the flag must not ship at all, otherwise a
        // remembered ON keeps asking for an injection nobody configured.
        await rememberInjection();

        await tester.pumpWidget(queueFormScreen(archiveDraft()));
        await tester.pumpAndSettle();
        await submitQueueForm(tester);

        expect(capturedBody?.containsKey('gcode_injection'), isFalse);
      },
    );

    testWidgets(
      'a target model with no snippet says nothing will be injected',
      (tester) async {
        // Snippets exist, but for another model — the scheduler prints the file
        // untouched and says so only in its own log.
        await tester.pumpWidget(
          queueFormScreen(archiveDraft(), snippets: {'A1 mini'}),
        );
        await tester.pumpAndSettle();
        await revealFlags(tester);

        expect(
          find.text(formL10n.queueEditGcodeInjectionNoSnippet('X2D')),
          findsNothing,
          reason: 'an unticked option has nothing to warn about',
        );

        await tapInjection(tester);

        expect(
          find.text(formL10n.queueEditGcodeInjectionNoSnippet('X2D')),
          findsAtLeastNWidgets(1),
        );
      },
    );

    testWidgets('the warning is where the printer is chosen, without scrolling', (
      tester,
    ) async {
      // The reported hole: someone who only comes in to change the printer never
      // reaches the checkbox at the bottom, so the note has to be where the
      // choice is made.
      await rememberInjection();

      await tester.pumpWidget(
        queueFormScreen(archiveDraft(), snippets: {'A1 mini'}),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(formL10n.queueEditGcodeInjectionNoSnippet('X2D')),
        findsOneWidget,
        reason: 'the Target section is on the first screen of the form',
      );
    });

    testWidgets('the warning is read out once, not once per copy', (
      tester,
    ) async {
      // The same sentence is deliberately shown twice — next to the checkbox
      // and up in the target section. Marking both as live regions would read
      // it out twice in a row, so only the one that answers the tap does.
      final handle = tester.ensureSemantics();
      await rememberInjection();

      await tester.pumpWidget(
        queueFormScreen(archiveDraft(), snippets: {'A1 mini'}),
      );
      await tester.pumpAndSettle();
      await revealFlags(tester);

      final sentence = find.text(
        formL10n.queueEditGcodeInjectionNoSnippet('X2D'),
      );
      expect(sentence, findsWidgets);
      expect(
        find.ancestor(
          of: sentence,
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.liveRegion == true,
          ),
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('editing without snippets does not rewrite the stored flag', (
      tester,
    ) async {
      await tester.pumpWidget(
        queueFormScreen(
          QueueItem.fromJson({
            'id': 5,
            'position': 1,
            'status': 'pending',
            'archive_id': 77,
            'printer_id': 1,
            'gcode_injection': true,
          }),
          schedule: QueueScheduleType.queue,
          mode: QueueEditMode.edit,
        ),
      );
      await tester.pumpAndSettle();

      await submitQueueForm(tester, edit: true);

      expect(
        capturedBody?.containsKey('gcode_injection'),
        isFalse,
        reason: 'checkbox off screen — the server value must not be cleared',
      );
    });
  });

  group('tri-state calibrations', () {
    /// The item the edit tests start from: stored `auto` on bed levelling, which
    /// is the value a two-state form must not quietly rewrite.
    QueueItem storedAuto() => QueueItem.fromJson({
      'id': 5,
      'position': 1,
      'status': 'pending',
      'archive_id': 77,
      'printer_id': 1,
      'sliced_for_model': 'X2D',
      'bed_levelling': 'auto',
      'flow_cali': 'on',
      'nozzle_offset_cali': 'auto',
    });

    testWidgets('an older server does not offer the Auto position', (
      tester,
    ) async {
      await tester.pumpWidget(queueFormScreen(archiveDraft()));
      await tester.pumpAndSettle();

      expect(
        find.text(formL10n.commonAuto),
        findsNothing,
        reason: 'the server has nowhere to store auto — do not promise it',
      );
      expect(find.byType(Switch), isNot(findsNothing));
    });

    testWidgets('a 1.2.5 server offers Auto / On / Off', (tester) async {
      await tester.pumpWidget(queueFormScreen(archiveDraft(), triState: true));
      await tester.pumpAndSettle();

      // Three calibration fields on screen (levelling, flow, nozzle offset).
      expect(find.text(formL10n.commonAuto), findsNWidgets(3));
    });

    testWidgets('a chosen Auto reaches the server as auto', (tester) async {
      await tester.pumpWidget(queueFormScreen(archiveDraft(), triState: true));
      await tester.pumpAndSettle();

      await tester.tap(find.text(formL10n.commonAuto).first);
      await tester.pumpAndSettle();
      await submitQueueForm(tester);

      expect(capturedBody?['bed_levelling'], 'auto');
    });

    testWidgets('a chosen Auto is remembered for the next print', (
      tester,
    ) async {
      // The tri-state is remembered by the same mechanism as the switches: `on`
      // to start with for anyone who never configured it, then whatever they
      // last picked. The serialization itself is covered by print_options_test;
      // what matters here is that the form really saves it.
      await tester.pumpWidget(queueFormScreen(archiveDraft(), triState: true));
      await tester.pumpAndSettle();

      await tester.tap(find.text(formL10n.commonAuto).first);
      await tester.pumpAndSettle();
      await submitQueueForm(tester);

      expect(storedPrintOptions().bedLevelling, CalibrationOption.auto);
      expect(
        storedPrintOptions().flowCali,
        CalibrationOption.on,
        reason: 'what was untouched stays what it was',
      );
    });

    testWidgets('the next print starts from the remembered Auto', (
      tester,
    ) async {
      await queueFormPrefs.setString(
        'print_options',
        const PrintOptions(
          bedLevelling: CalibrationOption.auto,
          flowCali: CalibrationOption.on,
          vibrationCali: true,
          layerInspect: true,
          timelapse: false,
          nozzleOffsetCali: CalibrationOption.auto,
        ).encode(),
      );

      await tester.pumpWidget(queueFormScreen(archiveDraft(), triState: true));
      await tester.pumpAndSettle();
      await submitQueueForm(tester);

      // Without touching a single option: what was remembered goes to the server.
      expect(capturedBody?['bed_levelling'], 'auto');
      expect(capturedBody?['nozzle_offset_cali'], 'auto');
      expect(
        capturedBody?['flow_cali'],
        true,
        reason: 'on travels as a boolean — every server generation reads it',
      );
    });

    testWidgets('a remembered Auto on an old server: the screen does not lie', (
      tester,
    ) async {
      // The only way `auto` reaches an old server: chosen on a newer one and
      // remembered, then the app pointed at an older one. The form then draws a
      // two-state switch in the ON position, and ON is what has to be saved.
      // Before this the key dropped out of the body, and the server's default
      // for `flow_cali` is `false` — the user saw on and got off.
      await queueFormPrefs.setString(
        'print_options',
        const PrintOptions(
          bedLevelling: CalibrationOption.auto,
          flowCali: CalibrationOption.auto,
          vibrationCali: true,
          layerInspect: true,
          timelapse: false,
          nozzleOffsetCali: CalibrationOption.auto,
        ).encode(),
      );

      await tester.pumpWidget(queueFormScreen(archiveDraft()));
      await tester.pumpAndSettle();

      expect(
        find.text(formL10n.commonAuto),
        findsNothing,
        reason: 'old server — there is no third state',
      );
      expect(
        tester.widgetList<Switch>(find.byType(Switch)).first.value,
        isTrue,
        reason: 'auto draws as on',
      );

      await submitQueueForm(tester);

      expect(capturedBody?['bed_levelling'], true);
      expect(
        capturedBody?['flow_cali'],
        true,
        reason: 'this is the point: the switch says on, so on is what is sent',
      );
      expect(capturedBody?['nozzle_offset_cali'], true);
    });

    testWidgets('an untouched auto is not overwritten on edit', (tester) async {
      // A two-state form draws auto as ON. Sending that back as `true` would
      // rewrite the user's auto as on — a field they never touched must not be
      // sent at all.
      await tester.pumpWidget(
        queueFormScreen(
          storedAuto(),
          schedule: QueueScheduleType.queue,
          mode: QueueEditMode.edit,
        ),
      );
      await tester.pumpAndSettle();

      await submitQueueForm(tester, edit: true);

      expect(capturedBody?.containsKey('bed_levelling'), isFalse);
      expect(capturedBody?.containsKey('nozzle_offset_cali'), isFalse);
      expect(
        capturedBody?.containsKey('flow_cali'),
        isFalse,
        reason: 'on is untouched too',
      );
    });

    testWidgets('a changed field is sent as usual', (tester) async {
      await tester.pumpWidget(
        queueFormScreen(
          storedAuto(),
          schedule: QueueScheduleType.queue,
          mode: QueueEditMode.edit,
        ),
      );
      await tester.pumpAndSettle();

      // The first switch is bed levelling — auto draws as ON, so tapping it
      // sets off.
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      await submitQueueForm(tester, edit: true);

      expect(capturedBody?['bed_levelling'], false);
      expect(capturedBody?.containsKey('flow_cali'), isFalse);
    });
  });
}
