import 'dart:typed_data';

import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/core/models/spool_label.dart';
import 'package:bambuddy_mobile/core/network/label_printer_discovery.dart';
import 'package:bambuddy_mobile/core/settings/label_print_prefs.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/data/inventory_repository.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:bambuddy_mobile/data/label_printer_repository.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_providers.dart';
import 'package:bambuddy_mobile/features/label_printer/label_printer_providers.dart';
import 'package:dio/dio.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_screen.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

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

  @override
  Future<Uint8List> renderLabels(SpoolLabelRequest labelRequest) async {
    request = labelRequest;
    return Uint8List.fromList([1, 2, 3]);
  }
}

class _RecordingLabelPrinter extends LabelPrinterRepository {
  _RecordingLabelPrinter() : super(Dio());

  Uint8List? sent;
  int? copies;
  bool? cutAtEnd;
  int? cutEvery;

  @override
  Future<void> printPdf(
    Uint8List pdf, {
    required String filename,
    int copies = 1,
    bool cutAtEnd = true,
    int cutEvery = 0,
  }) async {
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

class _NoUrl extends LabelPrinterUrlNotifier {
  @override
  String? build() => null;

  // The real one reads preferences these tests do not provide.
  @override
  Future<void> refresh({
    Stream<List<DiscoveredLabelPrinter>> Function()? discover,
  }) async {}
}

class _ChosenUrl extends LabelPrinterUrlNotifier {
  @override
  String? build() => 'http://10.0.0.5:8000';

  // The real one reads preferences these tests do not provide.
  @override
  Future<void> refresh({
    Stream<List<DiscoveredLabelPrinter>> Function()? discover,
  }) async {}
}

class _NullProfile extends ServerProfileNotifier {
  @override
  ServerProfile? build() => null;
}

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('pl'));
  });

  /// Opens the label sheet from the app bar and presses Print, which is what
  /// raises the stock picker.
  Future<_CapturingRepository> openTemplatePicker(
    WidgetTester tester, {
    required bool startingPositionSupported,
    AsyncValue<bool>? gate,
  }) async {
    final repo = _CapturingRepository();
    await pumpPhone(
      tester,
      const InventoryScreen(),
      overrides: [
        inventoryProvider.overrideWith(_CapturingInventory.new),
        serverProfileProvider.overrideWith(_NullProfile.new),
        labelPrinterUrlProvider.overrideWith(_NoUrl.new),
        labelPrintPrefsProvider.overrideWith(_MemoryPrefs.new),
        labelFieldsProvider.overrideWithValue(const AsyncData(false)),
        inventoryRepositoryProvider.overrideWithValue(repo),
        labelStartingPositionProvider.overrideWithValue(
          gate ?? AsyncData(startingPositionSupported),
        ),
      ],
    );
    await settle(tester);

    await tester.tap(find.byTooltip(l10n.inventoryLabelsPrintAll));
    await settle(tester);
    await tester.tap(find.text('${l10n.inventoryLabelsPrint} (1)'));
    await settle(tester);
    return repo;
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
    await tester.tap(find.text(l10n.inventoryLabelsPrint));
    await settle(tester);
  }

  testWidgets('an Avery sheet asks which slot to start at', (tester) async {
    final repo = await openTemplatePicker(
      tester,
      startingPositionSupported: true,
    );
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
      await pickTemplate(tester, l10n.inventoryLabelsBox40);
      expect(find.text(l10n.inventoryLabelsStartTitle), findsNothing);
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
    await pickTemplate(tester, l10n.inventoryLabelsAveryL7160);
    expect(find.text(l10n.inventoryLabelsStartTitle), findsNothing);
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
      await pickTemplate(tester, l10n.inventoryLabelsAveryL7160);
      expect(find.text(l10n.inventoryLabelsStartTitle), findsNothing);
      await pressPrint(tester);

      expect(repo.request!.startingPosition, 1);
    },
  );

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

    /// Opens the label sheet, picks the 62 x 29 stock and stops on the options
    /// sheet.
    Future<ProviderContainer> openOptions(
      WidgetTester tester, {
      bool chosen = false,
      bool fieldsGate = false,
      _RecordingLabelPrinter? printer,
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
          if (printer != null)
            labelPrinterRepositoryProvider.overrideWithValue(printer),
        ],
      );
      await settle(tester);
      await tester.tap(find.byTooltip(l10n.inventoryLabelsPrintAll));
      await settle(tester);
      await tester.tap(find.text('${l10n.inventoryLabelsPrint} (1)'));
      await settle(tester);
      await pickTemplate(tester, l10n.inventoryLabelsBox62);
      return ProviderScope.containerOf(
        tester.element(find.byType(InventoryScreen)),
      );
    }

    testWidgets('without a server the row leads to its setup', (tester) async {
      await openOptions(tester);
      expect(find.text(l10n.labelPrinterSetUp), findsOneWidget);
      expect(find.text(l10n.labelSendPrinter), findsNothing);
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
          child: MaterialApp.router(
            locale: const Locale('pl'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
        ),
      );
      await settle(tester);
      await tester.tap(find.byTooltip(l10n.inventoryLabelsPrintAll));
      await settle(tester);
      await tester.tap(find.text('${l10n.inventoryLabelsPrint} (1)'));
      await settle(tester);
      await pickTemplate(tester, l10n.inventoryLabelsBox62);

      await tapOption(tester, find.text(l10n.labelPrinterSetUp));
      await settle(tester);

      expect(find.text('LABEL PRINTER'), findsOneWidget);
    });

    testWidgets('a chosen server is where the labels go by default', (
      tester,
    ) async {
      final printer = _RecordingLabelPrinter();
      await openOptions(tester, chosen: true, printer: printer);
      expect(find.text(l10n.labelPrinterSetUp), findsNothing);

      await tester.tap(find.text(l10n.inventoryLabelsPrint));
      await settle(tester);

      expect(printer.sent, [1, 2, 3]);
      expect(printer.copies, 1);
      expect(printer.cutAtEnd, isTrue);
      expect(printer.cutEvery, 0);
      expect(find.text(l10n.labelPrinterSent), findsOneWidget);
    });

    testWidgets('copies and the cutter options reach the server', (
      tester,
    ) async {
      final printer = _RecordingLabelPrinter();
      await openOptions(tester, chosen: true, printer: printer);

      await tapOption(tester, find.byTooltip(l10n.copiesMore));
      await tapOption(tester, find.byTooltip(l10n.copiesMore));
      await tapOption(tester, find.text(l10n.labelPrinterCutAtEnd));
      await tapOption(tester, find.byTooltip(l10n.labelCutEveryMore));
      await tapOption(tester, find.byTooltip(l10n.labelCutEveryMore));
      await settle(tester);
      await tester.tap(find.text(l10n.inventoryLabelsPrint));
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
      expect(find.text(l10n.labelPrinterCopies), findsOneWidget);

      await tapOption(tester, find.text(l10n.labelSendShare));
      await settle(tester);
      expect(find.text(l10n.labelPrinterCopies), findsNothing);
    });

    testWidgets('an older server is not offered lines or PNG', (tester) async {
      await openOptions(tester);
      expect(find.text(l10n.labelFieldsTitle), findsNothing);
      expect(find.text('PNG'), findsNothing);
    });

    testWidgets('unchanged lines are not sent at all', (tester) async {
      await openOptions(tester, fieldsGate: true);
      await tester.tap(find.text(l10n.inventoryLabelsPrint));
      await settle(tester);

      expect(rendering.request!.fields, isNull);
    });

    testWidgets('a changed selection is sent, and remembered per stock', (
      tester,
    ) async {
      final container = await openOptions(tester, fieldsGate: true);
      await tapOption(tester, find.text(l10n.labelFieldBrand));
      await tapOption(tester, find.text(l10n.labelFieldMaterialNumber));
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

      await tester.tap(find.text(l10n.inventoryLabelsPrint));
      await settle(tester);
      expect(rendering.request!.fields, isNot(contains(SpoolLabelField.brand)));
      expect(
        rendering.request!.fields,
        contains(SpoolLabelField.materialNumber),
      );
    });

    testWidgets('reset puts the default lines back', (tester) async {
      final container = await openOptions(tester, fieldsGate: true);
      await tapOption(tester, find.text(l10n.labelFieldBrand));
      await settle(tester);
      // Back to the top, where the reset link is.
      await tester.drag(find.byType(Scrollable).last, const Offset(0, 800));
      await tester.pump();
      await tester.tap(find.text(l10n.labelFieldsReset));
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
      await tapOption(tester, find.text('PNG'));
      await settle(tester);
      await tapOption(tester, find.text('203 dpi'));
      await settle(tester);

      // A PNG cannot be printed or sent to the print server.
      expect(find.text(l10n.labelSendSystem), findsNothing);
      expect(find.text(l10n.labelSendPrinter), findsNothing);
      expect(find.text(l10n.labelSendSave), findsOneWidget);

      await tester.tap(find.text(l10n.inventoryLabelsPrint));
      await settle(tester);
      expect(rendering.request!.format, SpoolLabelFormat.png);
      expect(rendering.request!.dpi, 203);
    });

    testWidgets('what was chosen is still there the next time', (tester) async {
      final container = await openOptions(tester);
      await tapOption(tester, find.text(l10n.inventoryLabelsMonochrome));
      await settle(tester);

      expect(container.read(labelPrintPrefsProvider).monochrome, isTrue);
    });
  });
}
