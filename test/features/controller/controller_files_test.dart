import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/features/controller/controller_files.dart';
import 'package:bambuddy_mobile/features/controller/controller_screen.dart';
import 'package:bambuddy_mobile/features/dashboard/providers.dart';
import 'package:bambuddy_mobile/features/files/file_manager_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

const _window = MethodChannel('page.codeberg.morganmlgman.bambuddy/window');

/// Counts how often the library is built, which is how often it is fetched.
class _CountingLibrary extends FileManagerNotifier {
  _CountingLibrary(this.builds);

  final List<int> builds;

  @override
  Future<FileManagerState> build() async {
    builds.add(builds.length + 1);
    return const FileManagerState();
  }
}

void main() {
  setUpAll(loadAppFonts);

  late List<int> libraryBuilds;

  Future<void> pumpController(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(844, 390);
    addTearDown(tester.view.reset);
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_window, (call) async => null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, (_) async {
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(_window, null);
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });
    libraryBuilds = [];
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sp),
          fixedDashboardOverride(
            DashboardState(
              printers: [
                PrinterWithStatus(
                  printer: const Printer(id: 1, name: 'X1C Warsztat'),
                  status: const PrinterStatus(
                    id: 1,
                    connected: true,
                    state: 'IDLE',
                  ),
                ),
              ],
            ),
          ),
          inertStatusesOverride,
          inertSmartPlugsOverride,
          fileManagerProvider.overrideWith(
            () => _CountingLibrary(libraryBuilds),
          ),
        ],
        child: plApp(const ControllerScreen(printerId: 1)),
      ),
    );
    await settle(tester);
  }

  Future<void> select(WidgetTester tester, ControllerTab tab) async {
    await tester.tap(byLogId(tab.logId));
    await settle(tester);
  }

  testWidgets('Files is a tab of its own, between Filament and Settings', (
    tester,
  ) async {
    await pumpController(tester);

    final tabs = ControllerTab.values;
    expect(
      tabs.indexOf(ControllerTab.files),
      tabs.indexOf(ControllerTab.filament) + 1,
    );
    expect(
      tabs.indexOf(ControllerTab.settings),
      tabs.indexOf(ControllerTab.files) + 1,
    );
    expect(byLogId('controller.tab_files'), findsOneWidget);
    expect(find.text(pl.controllerTabFiles), findsOneWidget);
    expect(find.byType(ControllerFiles), findsNothing);

    await select(tester, ControllerTab.files);

    expect(find.byType(ControllerFiles), findsOneWidget);
  });

  testWidgets('nothing is fetched until Files is first selected', (
    tester,
  ) async {
    await pumpController(tester);

    await select(tester, ControllerTab.heat);
    await select(tester, ControllerTab.filament);

    expect(libraryBuilds, isEmpty);

    await select(tester, ControllerTab.files);

    expect(libraryBuilds, hasLength(1));
  });

  testWidgets('leaving Files and coming back does not start the library over', (
    tester,
  ) async {
    await pumpController(tester);

    await select(tester, ControllerTab.files);
    await select(tester, ControllerTab.heat);
    await select(tester, ControllerTab.files);
    await select(tester, ControllerTab.move);
    await select(tester, ControllerTab.files);

    expect(libraryBuilds, hasLength(1));
  });

  testWidgets('a keyboard does not resize the body', (tester) async {
    await pumpController(tester);
    await select(tester, ControllerTab.files);
    final before = tester.getSize(find.byType(ControllerFiles));

    tester.view.viewInsets = const FakeViewPadding(bottom: 220);
    addTearDown(tester.view.resetViewInsets);
    await settle(tester);

    expect(tester.getSize(find.byType(ControllerFiles)), before);
  });
}
