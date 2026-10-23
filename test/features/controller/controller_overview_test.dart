import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/features/common/media_image.dart';
import 'package:bambuddy_mobile/features/controller/controller_overview.dart';
import 'package:bambuddy_mobile/features/dashboard/providers.dart';
import 'package:bambuddy_mobile/features/dashboard/skip_objects_screen.dart';
import 'package:bambuddy_mobile/features/wall/wall_camera.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

const _phone = Size(844, 390);

PrinterStatus _status({
  String state = 'RUNNING',
  bool connected = true,
  String? cover,
}) => PrinterStatus(
  id: 1,
  connected: connected,
  state: state,
  progress: 62,
  remainingTime: 84,
  layerNum: 142,
  totalLayers: 310,
  currentPrint: 'Benchy.3mf',
  coverUrl: cover,
);

void main() {
  setUpAll(loadAppFonts);

  late RecordingCommands commands;

  Future<void> pumpOverview(
    WidgetTester tester,
    PrinterStatus status, {
    Map<String, Object> prefs = const {},
  }) async {
    useLogicalWindow(tester, _phone);
    commands = RecordingCommands();
    SharedPreferences.setMockInitialValues(prefs);
    final sp = await SharedPreferences.getInstance();
    await pumpPhone(
      tester,
      const Scaffold(body: ControllerOverview(printerId: 1)),
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sp),
        noServerProfileOverride,
        printerCommandsRepositoryProvider.overrideWithValue(commands),
        fixedDashboardOverride(
          DashboardState(
            printers: [
              PrinterWithStatus(
                printer: const Printer(id: 1, name: 'X1C Warsztat'),
                status: status,
              ),
            ],
          ),
        ),
        inertStatusesOverride,
        inertSmartPlugsOverride,
      ],
    );
    await tester.pump();
  }

  group('the job', () {
    testWidgets('shows what is printing and how far it got', (tester) async {
      await pumpOverview(tester, _status());

      expect(find.text('Benchy.3mf'), findsOneWidget);
      expect(find.text('62%'), findsOneWidget);
      expect(find.text('142/310'), findsOneWidget);
    });

    testWidgets('an idle printer has no job and nothing to pause', (
      tester,
    ) async {
      await pumpOverview(tester, _status(state: 'IDLE'));

      expect(find.text('Benchy.3mf'), findsNothing);
      expect(byLogId('controller.pause'), findsNothing);
      expect(byLogId('controller.stop'), findsNothing);
      expect(byLogId('controller.skip_objects'), findsNothing);
    });

    testWidgets('while preparing it shows no percentage', (tester) async {
      await pumpOverview(
        tester,
        const PrinterStatus(
          id: 1,
          connected: true,
          state: 'RUNNING',
          progress: 0,
          currentPrint: 'Benchy.3mf',
          stgCur: 1,
        ),
      );

      expect(find.text('0%'), findsNothing);
    });
  });

  group('pause, resume and stop', () {
    testWidgets('a running print offers pause and stop', (tester) async {
      await pumpOverview(tester, _status());

      expect(byLogId('controller.pause'), findsOneWidget);
      expect(byLogId('controller.stop'), findsOneWidget);
      expect(byLogId('controller.resume'), findsNothing);
    });

    testWidgets('a printer that does not answer offers neither', (
      tester,
    ) async {
      // Its last frame still says RUNNING, but a command could only fail.
      await pumpOverview(tester, _status(connected: false));

      expect(byLogId('controller.pause'), findsNothing);
      expect(byLogId('controller.stop'), findsNothing);
      expect(byLogId('controller.resume'), findsNothing);
    });

    testWidgets('a paused one offers resume instead of pause', (tester) async {
      await pumpOverview(tester, _status(state: 'PAUSE'));

      expect(byLogId('controller.resume'), findsOneWidget);
      expect(byLogId('controller.pause'), findsNothing);
    });

    testWidgets('pause sends the command for this printer', (tester) async {
      await pumpOverview(tester, _status());

      await tester.tap(byLogId('controller.pause'));
      await tester.pump();

      expect(commands.calls, ['pause:1']);
    });

    testWidgets('stop asks first, and cancelling sends nothing', (
      tester,
    ) async {
      await pumpOverview(tester, _status());

      await tester.tap(byLogId('controller.stop'));
      await settle(tester);

      expect(find.text(pl.ctrlStopConfirmTitle), findsOneWidget);
      expect(commands.calls, isEmpty);

      await tester.tap(byLogId('controller.stop_confirm.cancel'));
      await settle(tester);

      expect(commands.calls, isEmpty);
    });

    testWidgets('confirming the stop sends it', (tester) async {
      await pumpOverview(tester, _status());

      await tester.tap(byLogId('controller.stop'));
      await settle(tester);
      await tester.tap(byLogId('controller.stop_confirm.confirm'));
      await settle(tester);

      expect(commands.calls, ['stop:1']);
    });

    testWidgets('a refused session sees why, not buttons that fail', (
      tester,
    ) async {
      await pumpOverview(tester, _status());
      commands.error = const AuthException(AppErrorCode.forbidden);

      await tester.tap(byLogId('controller.pause'));
      await settle(tester);

      expect(find.text(pl.ctrlForbidden), findsOneWidget);
      expect(byLogId('controller.pause'), findsNothing);
      expect(byLogId('controller.stop'), findsNothing);
    });

    testWidgets('skip objects opens its screen for this printer', (
      tester,
    ) async {
      await pumpOverview(tester, _status());

      await tester.tap(byLogId('controller.skip_objects'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(SkipObjectsScreen), findsOneWidget);
    });
  });

  group('the picture', () {
    testWidgets('streams the camera while the setting is on', (tester) async {
      await pumpOverview(tester, _status());

      expect(find.byType(WallCamera), findsOneWidget);
      expect(find.text(pl.controllerLiveBadge), findsOneWidget);
      expect(find.text(pl.controllerPreviewBadge), findsNothing);
    });

    testWidgets('with the setting off it shows the file preview', (
      tester,
    ) async {
      await pumpOverview(
        tester,
        _status(cover: '/api/v1/printers/1/cover'),
        prefs: {'controller_prefs': '{"live_camera":false}'},
      );

      expect(find.byType(WallCamera), findsNothing);
      expect(find.text(pl.controllerPreviewBadge), findsOneWidget);
      expect(find.byType(MediaImage), findsOneWidget);
    });

    testWidgets('a file without a cover says "no preview"', (tester) async {
      await pumpOverview(
        tester,
        _status(),
        prefs: {'controller_prefs': '{"live_camera":false}'},
      );

      expect(find.byType(MediaImage), findsNothing);
      expect(find.text(pl.controllerNoPreview), findsOneWidget);
    });

    testWidgets('a preview that does not load says "no preview" too', (
      tester,
    ) async {
      // No server profile in the harness, so the picture cannot be fetched: the
      // same answer as a cover the server never produced.
      await pumpOverview(
        tester,
        _status(cover: '/api/v1/printers/1/cover'),
        prefs: {'controller_prefs': '{"live_camera":false}'},
      );

      expect(find.text(pl.controllerNoPreview), findsOneWidget);
    });

    testWidgets(
      'a printer that does not answer shows the preview, not a stream',
      (tester) async {
        await pumpOverview(
          tester,
          _status(connected: false, cover: '/api/v1/printers/1/cover'),
        );

        expect(find.byType(WallCamera), findsNothing);
        expect(find.text(pl.controllerPreviewBadge), findsOneWidget);
      },
    );
  });
}
