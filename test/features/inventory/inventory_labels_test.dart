import 'dart:typed_data';

import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/core/api/server_version_service.dart';
import 'package:bambuddy_mobile/core/models/current_user.dart';
import 'package:bambuddy_mobile/core/models/label_printer.dart';
import 'package:bambuddy_mobile/core/models/label_template.dart';
import 'package:bambuddy_mobile/core/models/spool_label.dart';
import 'package:bambuddy_mobile/core/network/label_printer_discovery.dart';
import 'package:bambuddy_mobile/core/settings/label_print_prefs.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/data/inventory_repository.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:bambuddy_mobile/data/label_printer_repository.dart';
import 'package:bambuddy_mobile/data/label_templates_repository.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_providers.dart';
import 'package:bambuddy_mobile/features/label_printer/label_printer_providers.dart';
import 'package:dio/dio.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_screen.dart';
import 'package:bambuddy_mobile/l10n/error_messages.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show PlatformException;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:go_router/go_router.dart';

import '../../contract/sent_writes.dart';
import '../../helpers.dart';

/// Where on an Avery sheet the print starts.
///
/// The whole question exists because a sheet is usually part-used, and the
/// answer only reaches a server new enough to read it — an older one takes the
/// number, says nothing, and prints from position 1 onto labels that are no
/// longer there.
class _CapturingInventory extends InventoryNotifier {
  @override
  Future<InventoryState> build() async => InventoryState(
    spools: const [Spool(id: 1, material: 'PLA', brand: 'Bambu')],
  );
}

/// Records the render request, then refuses — the refusal is what keeps the
/// bytes away from the platform print dialog, which no widget test can serve.
class _CapturingRepository extends InventoryRepository {
  _CapturingRepository() : super(_UnusedSource());

  SpoolLabelRequest? request;

  @override
  Future<Uint8List> renderLabels(SpoolLabelRequest labelRequest) async {
    request = labelRequest;
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

/// Hands out a PDF, so the print goes on to the destination under test.
class _RenderingRepository extends InventoryRepository {
  _RenderingRepository() : super(_UnusedSource());

  SpoolLabelRequest? request;

  /// What the server "answers" — a PNG's first bytes make the sheet treat it as
  /// one.
  Uint8List bytes = Uint8List.fromList([1, 2, 3]);

  @override
  Future<Uint8List> renderLabels(SpoolLabelRequest labelRequest) async {
    request = labelRequest;
    return bytes;
  }
}

class _RecordingLabelPrinter extends LabelPrinterRepository {
  _RecordingLabelPrinter() : super(Dio());

  Uint8List? sent;
  int? copies;
  bool? cutAtEnd;
  int? cutEvery;

  /// What the next send fails with.
  Object? error;

  @override
  Future<void> printPdf(
    Uint8List pdf, {
    required String filename,
    int copies = 1,
    bool cutAtEnd = true,
    int cutEvery = 0,
  }) async {
    if (error != null) throw error!;
    sent = pdf;
    this.copies = copies;
    this.cutAtEnd = cutAtEnd;
    this.cutEvery = cutEvery;
  }
}

/// The preferences without the disk: every change lands in memory only.
class _MemoryPrefs extends LabelPrintPrefsNotifier {
  @override
  LabelPrintPrefs build() => const LabelPrintPrefs();

  @override
  Future<void> set(LabelPrintPrefs prefs) async => state = prefs;
}

/// Preferences an earlier print left behind, kept in memory.
class _SeededPrefs extends LabelPrintPrefsNotifier {
  _SeededPrefs(this._seed);

  final LabelPrintPrefs _seed;

  @override
  LabelPrintPrefs build() => _seed;

  @override
  Future<void> set(LabelPrintPrefs prefs) async => state = prefs;
}

/// Preferences left on PNG by an earlier print.
class _PngPrefs extends LabelPrintPrefsNotifier {
  @override
  LabelPrintPrefs build() =>
      const LabelPrintPrefs(format: SpoolLabelFormat.png);

  @override
  Future<void> set(LabelPrintPrefs prefs) async => state = prefs;
}

/// A cache directory that fails, but not at once — after the label sheet has
/// closed, which is when the hand-off runs.
class _SlowFailingPaths extends PathProviderPlatform {
  _SlowFailingPaths(this.error);

  final Object error;

  @override
  Future<String?> getTemporaryPath() async {
    await Future<void>.delayed(const Duration(seconds: 1));
    throw error;
  }
}

class _NoUrl extends LabelPrinterUrlNotifier {
  @override
  String? build() => null;

  // The real one reads preferences these tests do not provide.
  @override
  Future<void> refresh({
    Stream<List<DiscoveredLabelPrinter>> Function()? discover,
    Future<bool> Function(String baseUrl)? verify,
  }) async {}
}

class _ChosenUrl extends LabelPrinterUrlNotifier {
  @override
  String? build() => 'http://10.0.0.5:8000';

  // The real one reads preferences these tests do not provide.
  @override
  Future<void> refresh({
    Stream<List<DiscoveredLabelPrinter>> Function()? discover,
    Future<bool> Function(String baseUrl)? verify,
  }) async {}
}

/// A template repository whose save fails with something the app did not
/// expect, as a bug would.
class _BrokenTemplates extends LabelTemplatesRepository {
  _BrokenTemplates(super.dio);

  @override
  Future<SavedLabelTemplate> create(String name, SheetLayout layout) async =>
      throw StateError('unreadable answer');
}

class _NullProfile extends ServerProfileNotifier {
  @override
  ServerProfile? build() => null;
}

void main() {
  /// Opens the label sheet from the app bar and presses Print, which is what
  /// raises the stock picker.
  Future<_CapturingRepository> openTemplatePicker(
    WidgetTester tester, {
    required bool startingPositionSupported,
    AsyncValue<bool>? gate,
    List<Override> extra = const [],
    LabelPrintPrefs Function()? prefs,
  }) async {
    final repo = _CapturingRepository();
    await pumpPhone(
      tester,
      const InventoryScreen(),
      overrides: [
        inventoryProvider.overrideWith(_CapturingInventory.new),
        serverProfileProvider.overrideWith(_NullProfile.new),
        labelPrinterUrlProvider.overrideWith(_NoUrl.new),
        labelPrintPrefsProvider.overrideWith(
          prefs == null ? _MemoryPrefs.new : () => _SeededPrefs(prefs()),
        ),
        labelFieldsProvider.overrideWithValue(const AsyncData(false)),
        inventoryRepositoryProvider.overrideWithValue(repo),
        labelStartingPositionProvider.overrideWithValue(
          gate ?? AsyncData(startingPositionSupported),
        ),
        ...extra,
      ],
    );
    await settle(tester);

    await tester.tap(find.byTooltip(pl.inventoryLabelsPrintAll));
    await settle(tester);
    await tester.tap(find.text('${pl.inventoryLabelsPrint} (1)'));
    await settle(tester);
    return repo;
  }

  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets('the label sheet keeps its list and Print button on screen at '
        'text $scale', (tester) async {
      tester.view.physicalSize = const Size(411, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpPhone(
        tester,
        const InventoryScreen(),
        overrides: [
          inventoryProvider.overrideWith(_CapturingInventory.new),
          serverProfileProvider.overrideWith(_NullProfile.new),
          labelPrinterUrlProvider.overrideWith(_NoUrl.new),
          labelPrintPrefsProvider.overrideWith(_MemoryPrefs.new),
          labelFieldsProvider.overrideWithValue(const AsyncData(false)),
          inventoryRepositoryProvider.overrideWithValue(_CapturingRepository()),
          labelStartingPositionProvider.overrideWithValue(
            const AsyncData(false),
          ),
        ],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      );
      await settle(tester);
      await tester.tap(find.byTooltip(pl.inventoryLabelsPrintAll));
      await settle(tester);

      expect(tester.takeException(), isNull);
      expect(
        tester
            .getRect(find.textContaining(pl.inventoryLabelsPrint).last)
            .bottom,
        lessThanOrEqualTo(800),
        reason: 'the footer stays on screen',
      );
      final pick = tester.getRect(find.text(pl.inventoryLabelsPickSpools));
      final row = tester.getRect(find.text('PLA · Bambu').last);
      expect(
        row.top,
        greaterThanOrEqualTo(pick.bottom),
        reason: 'the list starts below the filters, never over them',
      );
    });
  }

  /// Taps a stock card in the template sheet, scrolling it into range first:
  /// the sheet's list is lazy, and the two Avery entries sit below the fold.
  /// `hitTestable` because the list builds rows past its bottom edge, and a
  /// row that is built but not on screen swallows the tap.
  Future<void> pickTemplate(WidgetTester tester, String label) async {
    await tester.scrollUntilVisible(
      find.text(label).hitTestable(),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text(label));
    await settle(tester);
  }

  /// The step after the stock: the options sheet, closed with its Print button.
  Future<void> pressPrint(WidgetTester tester) async {
    await tester.tap(find.text(pl.inventoryLabelsPrint));
    await settle(tester);
  }

  testWidgets('an Avery sheet asks which slot to start at', (tester) async {
    final repo = await openTemplatePicker(
      tester,
      startingPositionSupported: true,
    );
    await pickTemplate(tester, pl.inventoryLabelsAveryL7160);

    expect(find.text(pl.inventoryLabelsStartTitle), findsOneWidget);
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
    await pressPrint(tester);
    expect(repo.request!.template, SpoolLabelTemplate.averyL7160);
    expect(repo.request!.startingPosition, 7);
  });

  testWidgets(
    'a roll template never asks — the server refuses any answer but 1',
    (tester) async {
      final repo = await openTemplatePicker(
        tester,
        startingPositionSupported: true,
      );
      await pickTemplate(tester, pl.inventoryLabelsBox40);
      expect(find.text(pl.inventoryLabelsStartTitle), findsNothing);
      await pressPrint(tester);
      expect(repo.request!.template, SpoolLabelTemplate.box40x30);
      expect(repo.request!.startingPosition, 1);
    },
  );

  testWidgets('a server that would ignore the answer is not asked either', (
    tester,
  ) async {
    // `LabelRequest` forbids no extra fields, so the sheet would print from 1
    // whatever was picked. Asking would cost a sheet of Avery stock to find out.
    final repo = await openTemplatePicker(
      tester,
      startingPositionSupported: false,
    );
    await pickTemplate(tester, pl.inventoryLabelsAveryL7160);
    expect(find.text(pl.inventoryLabelsStartTitle), findsNothing);
    await pressPrint(tester);

    expect(repo.request!.startingPosition, 1);
  });

  testWidgets(
    'a gate that failed prints from 1 rather than failing the print',
    (tester) async {
      // The flow waits on the gate outside a build; an error let through there
      // would end the print with nothing sent and nothing said.
      final repo = await openTemplatePicker(
        tester,
        startingPositionSupported: true,
        gate: AsyncError(StateError('no profile'), StackTrace.empty),
      );
      await pickTemplate(tester, pl.inventoryLabelsAveryL7160);
      expect(find.text(pl.inventoryLabelsStartTitle), findsNothing);
      await pressPrint(tester);

      expect(repo.request!.startingPosition, 1);
    },
  );

  group('custom sheets', () {
    const letter = SheetLayout(
      page: LabelPageSize.letter,
      labelWidthMm: 101.6,
      labelHeightMm: 50.8,
      columns: 2,
      rows: 5,
      topMm: 12.7,
      leftMm: 4.7,
      columnGapMm: 3.2,
    );

    /// A server that has custom sheets and the two saved on it.
    List<Override> served({bool supported = true, bool saved = true}) => [
      labelTemplatesSupportedProvider.overrideWithValue(AsyncData(supported)),
      labelTemplatesProvider.overrideWith(
        (ref) async => supported && saved
            ? [
                const SavedLabelTemplate(
                  id: 1,
                  name: 'Address labels',
                  layout: SheetLayout.starting,
                ),
                const SavedLabelTemplate(
                  id: 2,
                  name: 'Shipping labels',
                  layout: letter,
                ),
              ]
            : const [],
      ),
    ];

    /// A tall screen, so the whole form is built: its list is lazy, and the
    /// message under the preview sits below a phone's fold.
    void tall(WidgetTester tester) {
      tester.view.physicalSize = const Size(411, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    Future<void> openForm(WidgetTester tester) async {
      await pickTemplate(tester, pl.labelSheetCustom);
      expect(find.text(pl.labelSheetUse), findsOneWidget);
    }

    Finder field(String label) => find.widgetWithText(TextField, label);

    testWidgets('a saved sheet prints as "custom" with its own layout and '
        'capacity', (tester) async {
      final repo = await openTemplatePicker(
        tester,
        startingPositionSupported: true,
        extra: served(),
      );
      await pickTemplate(tester, 'Shipping labels');

      // 2 x 5: ten slots, and not an eleventh.
      expect(find.text(pl.inventoryLabelsStartTitle), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
      expect(find.text('11'), findsNothing);
      await tester.ensureVisible(find.text('4'));
      await settle(tester);
      await tester.tap(find.text('4'));
      await settle(tester);
      await pressPrint(tester);

      expect(repo.request!.template, SpoolLabelTemplate.custom);
      expect(repo.request!.layout, letter);
      expect(repo.request!.startingPosition, 4);
    });

    testWidgets('a saved sheet says what it is under its name', (tester) async {
      await openTemplatePicker(
        tester,
        startingPositionSupported: true,
        extra: served(),
      );
      await tester.scrollUntilVisible(
        find.text(pl.labelSheetSavedTitle).hitTestable(),
        120,
        scrollable: find.byType(Scrollable).last,
      );

      expect(
        find.text(pl.labelSheetSummary('A4', '63,5', '38,1', 21, 3, 7)),
        findsOneWidget,
      );
    });

    testWidgets('a server without custom sheets offers neither the list nor '
        'the form', (tester) async {
      tall(tester);
      await openTemplatePicker(
        tester,
        startingPositionSupported: true,
        extra: served(supported: false),
      );
      await tester.scrollUntilVisible(
        find.text(pl.inventoryLabelsAvery5160).hitTestable(),
        120,
        scrollable: find.byType(Scrollable).last,
      );

      expect(find.text(pl.labelSheetCustom), findsNothing);
      expect(find.text(pl.labelSheetSavedTitle), findsNothing);
    });

    testWidgets('a template saved by someone else on a server that then says '
        'no is not offered', (tester) async {
      tall(tester);
      // The listing still held rows, but the gate has settled on "absent".
      await openTemplatePicker(
        tester,
        startingPositionSupported: true,
        extra: [
          labelTemplatesSupportedProvider.overrideWithValue(
            const AsyncData(false),
          ),
          labelTemplatesProvider.overrideWith(
            (ref) async => const [
              SavedLabelTemplate(
                id: 1,
                name: 'Address labels',
                layout: SheetLayout.starting,
              ),
            ],
          ),
        ],
      );

      expect(find.text('Address labels'), findsNothing);
    });

    testWidgets('the form opens on the starting sheet and prints it', (
      tester,
    ) async {
      tall(tester);
      final repo = await openTemplatePicker(
        tester,
        startingPositionSupported: true,
        extra: served(saved: false),
      );
      await openForm(tester);

      expect(find.text(pl.labelSheetIncomplete), findsNothing);
      expect(
        find.text(pl.labelSheetSummary('A4', '63,5', '38,1', 21, 3, 7)),
        findsOneWidget,
      );

      await tester.tap(find.text(pl.labelSheetUse));
      await settle(tester);
      await tester.ensureVisible(find.text('1').first);
      await tester.tap(find.text('1').first);
      await settle(tester);
      await pressPrint(tester);

      expect(repo.request!.template, SpoolLabelTemplate.custom);
      expect(repo.request!.layout, SheetLayout.starting);
    });

    testWidgets('a layout that runs off the page says so and cannot be used', (
      tester,
    ) async {
      tall(tester);
      await openTemplatePicker(
        tester,
        startingPositionSupported: true,
        extra: served(),
      );
      await openForm(tester);

      await tester.enterText(field(pl.labelSheetColumns), '4');
      await settle(tester);

      // 7 + 4 x 63.5 + 3 x 2.5 = 268.5 mm on a 210 mm page.
      expect(find.text(pl.labelSheetTooWide('268,5', '210')), findsOneWidget);
      final use = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, pl.labelSheetUse),
      );
      expect(use.onPressed, isNull);

      await tester.enterText(field(pl.labelSheetColumns), '3');
      await settle(tester);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, pl.labelSheetUse),
            )
            .onPressed,
        isNotNull,
      );
    });

    testWidgets(
      'an empty field asks for a number, a comma is a decimal point',
      (tester) async {
        tall(tester);
        await openTemplatePicker(
          tester,
          startingPositionSupported: true,
          extra: served(),
        );
        await openForm(tester);

        await tester.enterText(field(pl.labelSheetLabelWidth), '');
        await settle(tester);
        expect(find.text(pl.labelSheetIncomplete), findsOneWidget);

        await tester.enterText(field(pl.labelSheetLabelWidth), '63,5');
        await settle(tester);
        expect(find.text(pl.labelSheetIncomplete), findsNothing);
      },
    );

    testWidgets('the page decides what fits: the same grid is too tall for '
        'Letter', (tester) async {
      tall(tester);
      await openTemplatePicker(
        tester,
        startingPositionSupported: true,
        extra: served(),
      );
      await openForm(tester);

      await tester.tap(find.text(pl.labelSheetPageA4));
      await settle(tester);
      await tester.tap(find.text(pl.labelSheetPageLetter).last);
      await settle(tester);

      // 15.15 + 7 x 38.1 = 281.85 mm on a 279.4 mm page.
      expect(
        find.text(pl.labelSheetTooTall('281,85', '279,4')),
        findsOneWidget,
      );
    });

    testWidgets('the sheet last used is what the form opens with, and the one '
        'just used is kept', (tester) async {
      tall(tester);
      late ProviderContainer container;
      await openTemplatePicker(
        tester,
        startingPositionSupported: true,
        extra: served(saved: false),
        prefs: () => const LabelPrintPrefs(customLayout: letter),
      );
      container = ProviderScope.containerOf(
        tester.element(find.byType(InventoryScreen)),
      );
      await openForm(tester);

      expect(
        find.text(pl.labelSheetSummary('Letter', '101,6', '50,8', 10, 2, 5)),
        findsOneWidget,
      );

      await tester.enterText(field(pl.labelSheetColumns), '1');
      await settle(tester);
      await tester.tap(find.text(pl.labelSheetUse));
      await settle(tester);

      expect(container.read(labelPrintPrefsProvider).customLayout?.columns, 1);
    });

    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('the form keeps its fields and Use button on screen at '
          'text $scale', (tester) async {
        tester.view.physicalSize = const Size(411, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await pumpPhone(
          tester,
          const InventoryScreen(),
          overrides: [
            inventoryProvider.overrideWith(_CapturingInventory.new),
            serverProfileProvider.overrideWith(_NullProfile.new),
            labelPrinterUrlProvider.overrideWith(_NoUrl.new),
            labelPrintPrefsProvider.overrideWith(_MemoryPrefs.new),
            labelFieldsProvider.overrideWithValue(const AsyncData(false)),
            inventoryRepositoryProvider.overrideWithValue(
              _CapturingRepository(),
            ),
            labelStartingPositionProvider.overrideWithValue(
              const AsyncData(false),
            ),
            ...served(),
          ],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
        );
        await settle(tester);
        await tester.tap(find.byTooltip(pl.inventoryLabelsPrintAll));
        await settle(tester);
        await tester.tap(find.text('${pl.inventoryLabelsPrint} (1)'));
        await settle(tester);
        await openForm(tester);

        expect(tester.takeException(), isNull);
        expect(
          tester.getRect(find.text(pl.labelSheetUse)).bottom,
          lessThanOrEqualTo(800),
          reason: 'the footer stays on screen',
        );
      });
    }
  });

  /// The writes behind "Save as template", "Save changes" and "Delete", sent
  /// through the real repository and recorded for the contract test that
  /// replays them on a live server.
  group('saving and deleting templates', () {
    late Dio dio;
    late DioAdapter adapter;
    late RequestLog sent;

    const address = {
      'id': 1,
      'name': 'Address labels',
      'layout': {
        'page': 'a4',
        'label_w_mm': 63.5,
        'label_h_mm': 38.1,
        'cols': 3,
        'rows': 7,
        'top_mm': 15.15,
        'left_mm': 7.0,
        'col_gap_mm': 2.5,
        'row_gap_mm': 0.0,
      },
      'created_at': '2026-11-01T10:00:00',
      'updated_at': '2026-11-01T10:00:00',
    };

    setUp(() {
      dio = testDio();
      adapter = mockServer(dio)
        ..onGet('/api/v1/label-templates', (s) => s.reply(200, [address]));
      sent = captureRequests(dio);
    });

    void tall(WidgetTester tester) {
      tester.view.physicalSize = const Size(411, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    Future<void> open(
      WidgetTester tester, {
      bool mayWrite = true,
      LabelTemplatesRepository? repo,
    }) async {
      tall(tester);
      await openTemplatePicker(
        tester,
        startingPositionSupported: true,
        extra: [
          labelTemplatesRepositoryProvider.overrideWithValue(
            repo ?? LabelTemplatesRepository(dio, ServerVersionService(dio)),
          ),
          labelTemplatesSupportedProvider.overrideWithValue(
            const AsyncData(true),
          ),
          permissionProvider(
            Permissions.inventoryUpdate,
          ).overrideWithValue(mayWrite),
        ],
      );
    }

    Finder nameField() => find.widgetWithText(TextField, pl.labelSheetName);
    Finder saveButton(String label) =>
        find.widgetWithText(OutlinedButton, label);

    Future<void> openOneOff(WidgetTester tester) async {
      await tester.tap(find.text(pl.labelSheetCustom));
      await settle(tester);
    }

    Future<void> openSaved(WidgetTester tester) async {
      await tester.tap(find.byTooltip(pl.labelSheetEdit));
      await settle(tester);
    }

    int listings() => sent.requests
        .where((r) => r.method == 'GET' && r.path.endsWith('/label-templates'))
        .length;

    testWidgets('a one-off sheet is saved under the name typed', (
      tester,
    ) async {
      adapter.onPost(
        '/api/v1/label-templates',
        (s) => s.reply(201, {...address, 'id': 9, 'name': 'Avery'}),
        data: Matchers.any,
      );
      await open(tester);
      await openOneOff(tester);
      expect(
        tester
            .widget<OutlinedButton>(saveButton(pl.labelSheetSaveAs))
            .onPressed,
        isNull,
        reason: 'no name yet',
      );

      await tester.enterText(nameField(), '  Avery  ');
      await settle(tester);
      await tester.tap(saveButton(pl.labelSheetSaveAs));
      await settle(tester);

      expectSentAsRecorded('label_template_create', writesOf(sent.requests));
      expect(find.text(pl.labelSheetSaved('Avery')), findsOneWidget);
      // The form now edits what it saved, and the list behind it was asked again.
      expect(saveButton(pl.labelSheetSaveChanges), findsOneWidget);
      expect(find.text(pl.labelSheetDelete), findsOneWidget);
      expect(listings(), greaterThan(1));
    });

    testWidgets('a saved sheet is replaced as a whole', (tester) async {
      adapter.onPut(
        '/api/v1/label-templates/1',
        (s) => s.reply(200, {...address, 'name': 'Address, 2 columns'}),
        data: Matchers.any,
      );
      await open(tester);
      await openSaved(tester);
      expect(
        tester.widget<TextField>(nameField()).controller!.text,
        'Address labels',
      );

      await tester.enterText(nameField(), 'Address, 2 columns');
      await tester.enterText(
        find.widgetWithText(TextField, pl.labelSheetColumns),
        '2',
      );
      await settle(tester);
      await tester.tap(saveButton(pl.labelSheetSaveChanges));
      await settle(tester);

      expectSentAsRecorded('label_template_update', writesOf(sent.requests));
      expect(
        find.text(pl.labelSheetSaved('Address, 2 columns')),
        findsOneWidget,
      );
    });

    testWidgets('a delete asks first, then removes the template', (
      tester,
    ) async {
      adapter.onDelete('/api/v1/label-templates/1', (s) => s.reply(204, null));
      await open(tester);
      await openSaved(tester);

      await tester.tap(find.text(pl.labelSheetDelete));
      await settle(tester);
      expect(writesOf(sent.requests), isEmpty, reason: 'asked first');
      expect(find.text(pl.labelSheetDeleteBody), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(pl.inventoryDelete),
        ),
      );
      await settle(tester);

      expectSentAsRecorded('label_template_delete', writesOf(sent.requests));
      expect(find.text(pl.labelSheetDeleted('Address labels')), findsOneWidget);
      expect(find.text(pl.labelSheetUse), findsNothing, reason: 'form closed');
      expect(listings(), greaterThan(1));
    });

    testWidgets('a cancelled delete sends nothing', (tester) async {
      await open(tester);
      await openSaved(tester);
      await tester.tap(find.text(pl.labelSheetDelete));
      await settle(tester);

      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(pl.cancel),
        ),
      );
      await settle(tester);

      expect(writesOf(sent.requests), isEmpty);
      expect(find.text(pl.labelSheetUse), findsOneWidget);
    });

    testWidgets('a name taken is said on the field, and clears once the name '
        'changes', (tester) async {
      adapter.onPost(
        '/api/v1/label-templates',
        (s) => s.reply(409, {
          'detail': 'A label template with this name already exists',
        }),
        data: Matchers.any,
      );
      await open(tester);
      await openOneOff(tester);

      await tester.enterText(nameField(), 'Address labels');
      await settle(tester);
      await tester.tap(saveButton(pl.labelSheetSaveAs));
      await settle(tester);

      expect(find.text(pl.labelSheetNameTaken), findsOneWidget);
      expect(saveButton(pl.labelSheetSaveAs), findsOneWidget);

      await tester.enterText(nameField(), 'Address labels 2');
      await settle(tester);
      expect(find.text(pl.labelSheetNameTaken), findsNothing);
    });

    testWidgets('a layout that does not fit cannot be saved', (tester) async {
      await open(tester);
      await openOneOff(tester);
      await tester.enterText(nameField(), 'Avery');
      await tester.enterText(
        find.widgetWithText(TextField, pl.labelSheetColumns),
        '9',
      );
      await settle(tester);

      expect(
        tester
            .widget<OutlinedButton>(saveButton(pl.labelSheetSaveAs))
            .onPressed,
        isNull,
      );
    });

    testWidgets('a session without inventory:update only uses them', (
      tester,
    ) async {
      await open(tester, mayWrite: false);

      expect(find.byTooltip(pl.labelSheetEdit), findsNothing);
      await openOneOff(tester);
      expect(nameField(), findsNothing);
      expect(find.text(pl.labelSheetSaveAs), findsNothing);
      expect(find.text(pl.labelSheetUse), findsOneWidget);
    });

    testWidgets('an unexpected error is reported and the form is usable '
        'again', (tester) async {
      await open(tester, repo: _BrokenTemplates(dio));
      await openOneOff(tester);
      await tester.enterText(nameField(), 'Avery');
      await settle(tester);

      final errors = <Object>[];
      await runZonedGuarded(() async {
        await tester.tap(saveButton(pl.labelSheetSaveAs));
        await settle(tester);
      }, (e, _) => errors.add(e));

      expect(errors.single, isA<StateError>());
      expect(
        tester
            .widget<OutlinedButton>(saveButton(pl.labelSheetSaveAs))
            .onPressed,
        isNotNull,
        reason: 'the form must not stay locked behind the error',
      );
    });
  });

  group('print options', () {
    late _RenderingRepository rendering;

    /// Taps [target], scrolling the options sheet to it first: the rows below
    /// the fold are not built until they are in range.
    Future<void> tapOption(WidgetTester tester, Finder target) async {
      await tester.scrollUntilVisible(
        target.hitTestable(),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(target);
      await tester.pump();
    }

    /// Opens the select named [field] and picks [option] from its menu.
    Future<void> pickOption(
      WidgetTester tester,
      String field,
      String option,
    ) async {
      // The label sits under the field's own text input, so it is scrolled to
      // by itself and tapped through the field rather than hit-tested.
      await tester.scrollUntilVisible(
        find.text(field),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text(field), warnIfMissed: false);
      await settle(tester);
      await tester.tap(find.text(option).last);
      await settle(tester);
    }

    /// Opens the label sheet, picks the 62 x 29 stock and stops on the options
    /// sheet.
    Future<ProviderContainer> openOptions(
      WidgetTester tester, {
      bool chosen = false,
      bool fieldsGate = false,
      _RecordingLabelPrinter? printer,
      String stock = '62x29',
      String templateLabel = '',
      bool infoNeverArrives = false,
    }) async {
      rendering = _RenderingRepository();
      await pumpPhone(
        tester,
        const InventoryScreen(),
        overrides: [
          inventoryProvider.overrideWith(_CapturingInventory.new),
          serverProfileProvider.overrideWith(_NullProfile.new),
          inventoryRepositoryProvider.overrideWithValue(rendering),
          labelStartingPositionProvider.overrideWithValue(
            const AsyncData(false),
          ),
          labelFieldsProvider.overrideWithValue(AsyncData(fieldsGate)),
          labelPrintPrefsProvider.overrideWith(_MemoryPrefs.new),
          labelPrinterUrlProvider.overrideWith(
            chosen ? _ChosenUrl.new : _NoUrl.new,
          ),
          // What `/info` says the printer holds.
          labelPrinterInfoProvider.overrideWith(
            (ref) => infoNeverArrives
                ? Completer<LabelPrinterInfo?>().future
                : Future.value(
                    LabelPrinterInfo(
                      model: 'QL-600',
                      connected: true,
                      labelId: stock,
                      maxCopies: 50,
                    ),
                  ),
          ),
          if (printer != null)
            labelPrinterRepositoryProvider.overrideWithValue(printer),
        ],
      );
      await settle(tester);
      await tester.tap(find.byTooltip(pl.inventoryLabelsPrintAll));
      await settle(tester);
      await tester.tap(find.text('${pl.inventoryLabelsPrint} (1)'));
      await settle(tester);
      await pickTemplate(
        tester,
        templateLabel.isEmpty ? pl.inventoryLabelsBox62 : templateLabel,
      );
      return ProviderScope.containerOf(
        tester.element(find.byType(InventoryScreen)),
      );
    }

    testWidgets('without a server the row leads to its setup', (tester) async {
      await openOptions(tester);
      expect(find.text(pl.labelPrinterSetUp), findsOneWidget);
      expect(find.text(pl.labelSendPrinter), findsNothing);
    });

    testWidgets('the setup row opens the label printer settings', (
      tester,
    ) async {
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const InventoryScreen()),
          GoRoute(
            path: '/settings/label-printer',
            builder: (_, _) => const Scaffold(body: Text('LABEL PRINTER')),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          retry: neverRetry,
          overrides: [
            inventoryProvider.overrideWith(_CapturingInventory.new),
            serverProfileProvider.overrideWith(_NullProfile.new),
            inventoryRepositoryProvider.overrideWithValue(
              _RenderingRepository(),
            ),
            labelStartingPositionProvider.overrideWithValue(
              const AsyncData(false),
            ),
            labelFieldsProvider.overrideWithValue(const AsyncData(false)),
            labelPrintPrefsProvider.overrideWith(_MemoryPrefs.new),
            labelPrinterUrlProvider.overrideWith(_NoUrl.new),
          ],
          child: plRouterApp(router),
        ),
      );
      await settle(tester);
      await tester.tap(find.byTooltip(pl.inventoryLabelsPrintAll));
      await settle(tester);
      await tester.tap(find.text('${pl.inventoryLabelsPrint} (1)'));
      await settle(tester);
      await pickTemplate(tester, pl.inventoryLabelsBox62);

      await tapOption(tester, find.text(pl.labelPrinterSetUp));
      await settle(tester);

      expect(find.text('LABEL PRINTER'), findsOneWidget);
    });

    testWidgets('a label server that refuses the login says so after the '
        'sheet closed', (tester) async {
      const refusal = AuthException(AppErrorCode.unauthorized);
      final printer = _RecordingLabelPrinter()..error = refusal;
      await openOptions(tester, chosen: true, printer: printer);

      await tester.tap(find.text(pl.inventoryLabelsPrint));
      await settle(tester);

      expect(find.text(refusal.localized(pl)), findsOneWidget);
      expect(find.text(pl.labelPrinterSent), findsNothing);
    });

    testWidgets('a chosen server is where the labels go by default', (
      tester,
    ) async {
      final printer = _RecordingLabelPrinter();
      await openOptions(tester, chosen: true, printer: printer);
      expect(find.text(pl.labelPrinterSetUp), findsNothing);

      await tester.tap(find.text(pl.inventoryLabelsPrint));
      await settle(tester);

      expect(printer.sent, [1, 2, 3]);
      expect(printer.copies, 1);
      expect(printer.cutAtEnd, isTrue);
      expect(printer.cutEvery, 0);
      expect(find.text(pl.labelPrinterSent), findsOneWidget);
    });

    testWidgets('a stock the printer does not hold is not the default', (
      tester,
    ) async {
      final printer = _RecordingLabelPrinter();
      await openOptions(
        tester,
        chosen: true,
        printer: printer,
        templateLabel: pl.inventoryLabelsBox40,
      );

      await tester.tap(find.text(pl.inventoryLabelsPrint));
      await settle(tester);

      // The print dialog, which a widget test cannot serve — what matters is
      // that the print server was not sent a label it would refuse.
      expect(printer.sent, isNull);
      expect(find.text(pl.labelPrinterSent), findsNothing);
    });

    testWidgets('the printer is still there to be picked for it', (
      tester,
    ) async {
      final printer = _RecordingLabelPrinter();
      await openOptions(
        tester,
        chosen: true,
        printer: printer,
        templateLabel: pl.inventoryLabelsBox40,
      );

      await pickOption(tester, pl.labelSendToTitle, pl.labelSendPrinter);
      await tester.tap(find.text(pl.inventoryLabelsPrint));
      await settle(tester);

      expect(printer.sent, [1, 2, 3]);
    });

    testWidgets('until the printer has said what it holds, the dialog is', (
      tester,
    ) async {
      final printer = _RecordingLabelPrinter();
      await openOptions(
        tester,
        chosen: true,
        printer: printer,
        infoNeverArrives: true,
      );

      await tester.tap(find.text(pl.inventoryLabelsPrint));
      await settle(tester);

      expect(printer.sent, isNull);
    });

    testWidgets('a printer holding other labels takes none of ours', (
      tester,
    ) async {
      final printer = _RecordingLabelPrinter();
      await openOptions(tester, chosen: true, printer: printer, stock: '54x29');

      await tester.tap(find.text(pl.inventoryLabelsPrint));
      await settle(tester);

      expect(printer.sent, isNull);
    });

    testWidgets('copies and the cutter options reach the server', (
      tester,
    ) async {
      final printer = _RecordingLabelPrinter();
      await openOptions(tester, chosen: true, printer: printer);

      await tapOption(tester, find.byTooltip(pl.copiesMore));
      await tapOption(tester, find.byTooltip(pl.copiesMore));
      await tapOption(tester, find.text(pl.labelPrinterCutAtEnd));
      await tapOption(tester, find.byTooltip(pl.labelCutEveryMore));
      await tapOption(tester, find.byTooltip(pl.labelCutEveryMore));
      await settle(tester);
      await tester.tap(find.text(pl.inventoryLabelsPrint));
      await settle(tester);

      expect(printer.copies, 3);
      expect(printer.cutAtEnd, isFalse);
      expect(printer.cutEvery, 2);
    });

    testWidgets('the printer options are only shown for the printer', (
      tester,
    ) async {
      await openOptions(
        tester,
        chosen: true,
        printer: _RecordingLabelPrinter(),
      );
      expect(find.text(pl.labelPrinterCopies), findsOneWidget);

      await pickOption(tester, pl.labelSendToTitle, pl.labelSendShare);
      await settle(tester);
      expect(find.text(pl.labelPrinterCopies), findsNothing);
    });

    testWidgets('an older server is not offered lines or PNG', (tester) async {
      await openOptions(tester);
      expect(find.text(pl.labelFieldsTitle), findsNothing);
      expect(find.text(pl.labelFormatTitle), findsNothing);
    });

    testWidgets('unchanged lines are not sent at all', (tester) async {
      await openOptions(tester, fieldsGate: true);
      await tester.tap(find.text(pl.inventoryLabelsPrint));
      await settle(tester);

      expect(rendering.request!.fields, isNull);
    });

    testWidgets('a changed selection is sent, and remembered per stock', (
      tester,
    ) async {
      final container = await openOptions(tester, fieldsGate: true);
      await tapOption(tester, find.text(pl.labelFieldBrand));
      await tapOption(tester, find.text(pl.labelFieldMaterialNumber));
      await settle(tester);

      expect(
        container
            .read(labelPrintPrefsProvider)
            .fieldsFor(SpoolLabelTemplate.box62x29),
        {
          SpoolLabelField.material,
          SpoolLabelField.hex,
          SpoolLabelField.name,
          SpoolLabelField.location,
          SpoolLabelField.qr,
          SpoolLabelField.spoolId,
          SpoolLabelField.materialNumber,
        },
      );
      // Another stock keeps its own lines.
      expect(
        container
            .read(labelPrintPrefsProvider)
            .fieldsFor(SpoolLabelTemplate.box40x30),
        SpoolLabelField.defaults,
      );

      await tester.tap(find.text(pl.inventoryLabelsPrint));
      await settle(tester);
      expect(rendering.request!.fields, isNot(contains(SpoolLabelField.brand)));
      expect(
        rendering.request!.fields,
        contains(SpoolLabelField.materialNumber),
      );
    });

    testWidgets('reset puts the default lines back', (tester) async {
      final container = await openOptions(tester, fieldsGate: true);
      await tapOption(tester, find.text(pl.labelFieldBrand));
      await settle(tester);
      // Back to the top, where the reset link is. The sheet's own list, not the
      // last scrollable: a text field built further down has one of its own.
      await tester.drag(
        find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axis == Axis.vertical,
            )
            .last,
        const Offset(0, 800),
      );
      await tester.pump();
      await tester.tap(find.text(pl.labelFieldsReset));
      await settle(tester);

      expect(
        container
            .read(labelPrintPrefsProvider)
            .fieldsFor(SpoolLabelTemplate.box62x29),
        SpoolLabelField.defaults,
      );
    });

    testWidgets('PNG takes a resolution and leaves out the printer', (
      tester,
    ) async {
      await openOptions(
        tester,
        chosen: true,
        fieldsGate: true,
        printer: _RecordingLabelPrinter(),
      );
      await pickOption(tester, pl.labelFormatTitle, 'PNG');
      await pickOption(tester, pl.labelDpiTitle, '203 dpi');
      await settle(tester);

      // A PNG cannot be printed or sent to the print server.
      await tester.tap(find.text(pl.labelSendToTitle), warnIfMissed: false);
      await settle(tester);
      expect(find.text(pl.labelSendSystem), findsNothing);
      expect(find.text(pl.labelSendPrinter), findsNothing);
      expect(find.text(pl.labelSendSave), findsOneWidget);

      await tester.tap(find.text(pl.inventoryLabelsPrint));
      await settle(tester);
      expect(rendering.request!.format, SpoolLabelFormat.png);
      expect(rendering.request!.dpi, 203);
    });

    testWidgets('what was chosen is still there the next time', (tester) async {
      final container = await openOptions(tester);
      await tapOption(tester, find.text(pl.inventoryLabelsMonochrome));
      await settle(tester);

      expect(container.read(labelPrintPrefsProvider).monochrome, isTrue);
    });

    testWidgets('the gate is settled before the sheet opens, not after', (
      tester,
    ) async {
      // PNG was left chosen by an earlier print. A sheet opened while the gate
      // was still out hid it, and the answer arriving afterwards then turned
      // the print into a PNG for a sheet that never offered one.
      final gate = StateProvider<AsyncValue<bool>>((_) => const AsyncLoading());
      await pumpPhone(
        tester,
        const InventoryScreen(),
        overrides: [
          inventoryProvider.overrideWith(_CapturingInventory.new),
          serverProfileProvider.overrideWith(_NullProfile.new),
          inventoryRepositoryProvider.overrideWithValue(_RenderingRepository()),
          labelStartingPositionProvider.overrideWithValue(
            const AsyncData(false),
          ),
          labelFieldsProvider.overrideWith((ref) => ref.watch(gate)),
          labelPrintPrefsProvider.overrideWith(_PngPrefs.new),
          labelPrinterUrlProvider.overrideWith(_NoUrl.new),
        ],
      );
      await settle(tester);
      await tester.tap(find.byTooltip(pl.inventoryLabelsPrintAll));
      await settle(tester);
      await tester.tap(find.text('${pl.inventoryLabelsPrint} (1)'));
      await settle(tester);
      await pickTemplate(tester, pl.inventoryLabelsBox62);

      expect(find.text(pl.labelOptionsTitle), findsNothing);

      ProviderScope.containerOf(
        tester.element(find.byType(InventoryScreen)),
      ).read(gate.notifier).state = const AsyncData(
        true,
      );
      await settle(tester);

      expect(find.text(pl.labelOptionsTitle), findsOneWidget);
      // Below the fold in a list that builds rows lazily.
      await tester.scrollUntilVisible(
        find.text(pl.labelFormatTitle),
        120,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axis == Axis.vertical,
            )
            .last,
      );
      expect(find.text(pl.labelFormatTitle), findsOneWidget);
    });

    // The device failing, not a bug: a full disk, a missing print service.
    for (final (name, error) in <(String, Object)>[
      ('a file error', const FileSystemException('disk full')),
      ('a platform error', PlatformException(code: 'no_print_service')),
    ]) {
      testWidgets('a hand-off that fails with $name after the sheet closed '
          'still says so', (tester) async {
        final previous = PathProviderPlatform.instance;
        PathProviderPlatform.instance = _SlowFailingPaths(error);
        addTearDown(() => PathProviderPlatform.instance = previous);

        final container = await openOptions(tester, fieldsGate: true);
        rendering.bytes = Uint8List.fromList([
          0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
        ]);
        await pickOption(tester, pl.labelFormatTitle, 'PNG');
        await tapOption(tester, find.text(pl.inventoryLabelsPrint));
        expect(
          container.read(labelPrintPrefsProvider).format,
          SpoolLabelFormat.png,
        );

        // The sheet closes at once; the cache directory fails a second later.
        // In steps: one long pump fires the timer before the frame that takes
        // the sheet down, and the sheet would still be there to report it.
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await settle(tester);

        expect(find.text(pl.inventoryLabelsFailed), findsOneWidget);
      });
    }
  });
}
