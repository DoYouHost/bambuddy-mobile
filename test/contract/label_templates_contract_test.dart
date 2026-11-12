import 'dart:typed_data';

import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/core/api/server_version_service.dart';
import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/core/models/label_template.dart';
import 'package:bambuddy_mobile/core/models/spool_label.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:bambuddy_mobile/data/label_templates_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';
import 'sent_writes.dart';

/// Custom label sheets (server #3296), against the real server: the saved list,
/// printing on a sheet of the user's own measures, and that the app's own
/// reading of "does it fit" agrees with the server's. An older server — which
/// the app also talks to — has neither route, and must say so by itself.
void main() {
  group('label templates contract', skip: contractSkipReason, () {
    late Dio dio;
    late NativeInventorySource source;
    late LabelTemplatesRepository templates;
    late bool hasTemplates;
    late int spoolId;
    final templateIds = <int>[];
    final stamp = DateTime.now().millisecondsSinceEpoch;

    setUpAll(() async {
      dio = await authenticatedDio();
      source = NativeInventorySource(dio);
      templates = LabelTemplatesRepository(dio, ServerVersionService(dio));
      final probe = await dio.get<dynamic>(
        Endpoints.labelTemplates,
        options: Options(validateStatus: (_) => true),
      );
      hasTemplates = probe.statusCode == 200;
      spoolId = (await source.createSpool(
        SpoolDraft(
          material: 'PLA',
          brand: 'Sheets $stamp',
          colorName: 'Teal',
          labelWeight: 1000,
        ),
      )).id;
    });

    tearDownAll(() async {
      final quiet = Options(validateStatus: (_) => true);
      await dio.delete<dynamic>(
        Endpoints.inventorySpool(spoolId),
        options: quiet,
      );
      for (final id in templateIds) {
        await dio.delete<dynamic>(Endpoints.labelTemplate(id), options: quiet);
      }
    });

    Future<SavedLabelTemplate> save(String name, SheetLayout layout) async {
      final saved = await templates.create('$name $stamp', layout);
      templateIds.add(saved.id);
      return saved;
    }

    Future<Uint8List> render(
      SheetLayout layout, {
      int startingPosition = 1,
      SpoolLabelFormat format = SpoolLabelFormat.pdf,
    }) => source.renderLabels(
      SpoolLabelRequest(
        spoolIds: [spoolId],
        template: SpoolLabelTemplate.custom,
        layout: layout,
        startingPosition: startingPosition,
        format: format,
      ),
    );

    /// PNG header: signature, then the IHDR chunk, whose first two fields are
    /// the width and the height.
    ({int width, int height}) pngSize(Uint8List png) {
      final header = ByteData.sublistView(png, 16, 24);
      return (width: header.getUint32(0), height: header.getUint32(4));
    }

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

    test('a server without them answers 404, and the app reads that', () async {
      if (hasTemplates) {
        markTestSkipped('server has label templates');
        return;
      }
      expect(await templates.list(), isEmpty);
      expect(await templates.capability.supported, isFalse);
    });

    test(
      'an older server refuses a custom sheet rather than drop it',
      () async {
        if (hasTemplates) {
          markTestSkipped('server has label templates');
          return;
        }
        await expectLater(
          render(SheetLayout.starting),
          throwsA(
            isA<AppApiException>().having((e) => e.statusCode, 'status', 422),
          ),
        );
      },
    );

    test('a saved sheet comes back as it was sent', () async {
      if (!hasTemplates) {
        markTestSkipped('server predates #3296');
        return;
      }
      final saved = await save('Round trip', letter);
      expect(saved.name, 'Round trip $stamp');
      expect(saved.layout, letter);

      final listed = await templates.list();
      expect(listed.where((t) => t.id == saved.id).single.layout, letter);
      expect(await templates.capability.supported, isTrue);
    });

    test('a rename and a new layout replace the whole template', () async {
      if (!hasTemplates) {
        markTestSkipped('server predates #3296');
        return;
      }
      final saved = await save('Before', SheetLayout.starting);
      final updated = await templates.update(saved.id, 'After $stamp', letter);

      expect(updated.id, saved.id);
      expect(updated.name, 'After $stamp');
      expect(updated.layout, letter);
    });

    test('a name taken ignoring case is a 409, on create and rename', () async {
      if (!hasTemplates) {
        markTestSkipped('server predates #3296');
        return;
      }
      final saved = await save('Taken', SheetLayout.starting);
      final other = await save('Other', SheetLayout.starting);

      // Started one at a time: a future built ahead of its `expectLater` would
      // fail unobserved while the first is still being awaited.
      for (final attempt in [
        () => templates.create(saved.name.toUpperCase(), letter),
        () => templates.update(other.id, saved.name.toLowerCase(), letter),
      ]) {
        await expectLater(
          attempt(),
          throwsA(
            isA<AppApiException>().having((e) => e.statusCode, 'status', 409),
          ),
        );
      }
      // Saving a template again under its own name is not a clash.
      await templates.update(saved.id, saved.name, letter);
    });

    test('a delete removes it, and a second one is a 404', () async {
      if (!hasTemplates) {
        markTestSkipped('server predates #3296');
        return;
      }
      final saved = await save('Doomed', SheetLayout.starting);
      await templates.delete(saved.id);

      expect((await templates.list()).where((t) => t.id == saved.id), isEmpty);
      await expectLater(
        templates.delete(saved.id),
        throwsA(
          isA<AppApiException>().having((e) => e.statusCode, 'status', 404),
        ),
      );
    });

    test(
      'a layout is printable when the app says it is, and not otherwise',
      () async {
        if (!hasTemplates) {
          markTestSkipped('server predates #3296');
          return;
        }
        SheetLayout of({
          double width = 63.5,
          double height = 38.1,
          int columns = 3,
          int rows = 7,
          double top = 15.15,
          double left = 7,
          double gap = 2.5,
          LabelPageSize page = LabelPageSize.a4,
        }) => SheetLayout(
          page: page,
          labelWidthMm: width,
          labelHeightMm: height,
          columns: columns,
          rows: rows,
          topMm: top,
          leftMm: left,
          columnGapMm: gap,
        );

        // One case per condition of `SheetLayout.problem()`, and the boundaries
        // either side of the page's fit tolerance.
        final cases = {
          'fits': of(),
          'label too narrow': of(width: 39.9, columns: 1),
          'label too short': of(height: 19.9, rows: 1),
          'length over 300': of(width: 300.1, columns: 1),
          'no columns': of(columns: 0),
          'too many columns': of(columns: 21, width: 40, left: 0, gap: 0),
          'no rows': of(rows: 0),
          'negative margin': of(top: -1),
          'too wide': of(columns: 4),
          'too tall': of(rows: 8),
          'Letter, too tall': of(page: LabelPageSize.letter),
          'Letter, fits': of(page: LabelPageSize.letter, rows: 6),
          'a hundredth over': of(columns: 1, rows: 1, width: 203.009),
          'two hundredths over': of(columns: 1, rows: 1, width: 203.02),
        };
        for (final MapEntry(:key, :value) in cases.entries) {
          final accepted = await dio.post<dynamic>(
            Endpoints.labelTemplates,
            data: {'name': 'Fit $key $stamp', 'layout': value.toJson()},
            options: Options(validateStatus: (_) => true),
          );
          if (accepted.statusCode == 201) {
            templateIds.add((accepted.data as Map)['id'] as int);
          }
          expect(
            accepted.statusCode == 201,
            value.problem == null,
            reason: '$key: the server said ${accepted.statusCode}',
          );
        }
      },
    );

    test('what the template editor's buttons send is accepted and stored', () async {
      if (!hasTemplates) {
        markTestSkipped('server predates #3296');
        return;
      }
      final itemIn = RegExp(r'(?<=/label-templates/)\d+');

      // "Save as template": the recorded POST, read back from the list.
      final created = (await replayWrites(
        dio,
        recordedWrites('label_template_create'),
      )).single;
      expect(created.statusCode, 201, reason: '${created.data}');
      final id = (created.data as Map)['id'] as int;
      templateIds.add(id);
      final sentName =
          (recordedWrites('label_template_create').single.body as Map)['name'];
      expect(
        (await templates.list()).where((t) => t.id == id).single.name,
        sentName,
      );

      // "Save as new" from an edit: the same POST, another name.
      final copied = (await replayWrites(
        dio,
        recordedWrites('label_template_save_as_new'),
      )).single;
      expect(copied.statusCode, 201, reason: '${copied.data}');
      templateIds.add((copied.data as Map)['id'] as int);

      // "Save changes": the recorded PUT, aimed at the template just made.
      final updated = (await replayWrites(
        dio,
        recordedWrites('label_template_update'),
        item: id,
        itemIn: itemIn,
      )).single;
      expect(updated.statusCode, 200, reason: '${updated.data}');
      final stored = (await templates.list()).where((t) => t.id == id).single;
      final sentUpdate =
          recordedWrites('label_template_update').single.body as Map;
      expect(stored.name, sentUpdate['name']);
      expect(stored.layout.columns, (sentUpdate['layout'] as Map)['cols']);

      // "Delete": the recorded DELETE.
      final deleted = (await replayWrites(
        dio,
        recordedWrites('label_template_delete'),
        item: id,
        itemIn: itemIn,
      )).single;
      expect(deleted.statusCode, 204, reason: '${deleted.data}');
      expect((await templates.list()).where((t) => t.id == id), isEmpty);
    });

    test('a custom sheet prints on its own page, in either format', () async {
      if (!hasTemplates) {
        markTestSkipped('server predates #3296');
        return;
      }
      expect(SpoolLabelFile.of(await render(letter)), SpoolLabelFile.pdf);

      final png = pngSize(await render(letter, format: SpoolLabelFormat.png));
      // US Letter, not the A4 the built-in sheet sits on.
      expect(png.width / png.height, closeTo(215.9 / 279.4, 0.01));
    });

    test('a PNG of sheets past pages × dpi is refused, as the app says before '
        'it is asked', () async {
      if (!hasTemplates) {
        markTestSkipped('server predates #3296');
        return;
      }
      const single = SheetLayout(
        page: LabelPageSize.a4,
        labelWidthMm: 100,
        labelHeightMm: 100,
        columns: 1,
        rows: 1,
        topMm: 0,
        leftMm: 0,
      );
      final stock = LabelStock(SpoolLabelTemplate.custom, layout: single);
      // One page a label: the first count past 15 000 at each resolution. Only
      // the refusal is asked for — it comes before anything is rendered.
      for (final (labels, dpi) in const [(26, 600), (51, 300), (74, 203)]) {
        final over = pngSheetOverCap(
          stock,
          labels: labels,
          startingPosition: 1,
          dpi: dpi,
        );
        expect(over, isNotNull, reason: '$labels at $dpi dpi');
        final res = await dio.post<dynamic>(
          Endpoints.inventoryLabels,
          data: {
            'spool_ids': [for (var i = 0; i < labels; i++) spoolId],
            'template': 'custom',
            'layout': single.toJson(),
            'format': 'png',
            'dpi': dpi,
          },
          options: Options(validateStatus: (_) => true),
        );
        expect(res.statusCode, 422, reason: '$labels at $dpi dpi: ${res.data}');
        expect(
          '${res.data}',
          contains('limited to ${over!.maxPages} sheet pages'),
        );
      }
    });

    test('a custom sheet starts within its own grid', () async {
      if (!hasTemplates) {
        markTestSkipped('server predates #3296');
        return;
      }
      // 10 labels on the sheet: the last slot is fine, the one after is not.
      expect(
        SpoolLabelFile.of(await render(letter, startingPosition: 10)),
        SpoolLabelFile.pdf,
      );
      await expectLater(
        render(letter, startingPosition: 11),
        throwsA(
          isA<AppApiException>().having((e) => e.statusCode, 'status', 422),
        ),
      );
    });

    test('the layout goes with "custom" and with no other template', () async {
      if (!hasTemplates) {
        markTestSkipped('server predates #3296');
        return;
      }
      final quiet = Options(validateStatus: (_) => true);
      final withLayout = await dio.post<dynamic>(
        Endpoints.inventoryLabels,
        data: {
          'spool_ids': [spoolId],
          'template': 'box_62x29',
          'layout': letter.toJson(),
        },
        options: quiet,
      );
      final without = await dio.post<dynamic>(
        Endpoints.inventoryLabels,
        data: {
          'spool_ids': [spoolId],
          'template': 'custom',
        },
        options: quiet,
      );

      expect(withLayout.statusCode, 422);
      expect(without.statusCode, 422);
    });
  });
}
