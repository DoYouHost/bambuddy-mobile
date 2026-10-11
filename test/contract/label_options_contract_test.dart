import 'dart:convert';
import 'dart:typed_data';

import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/core/api/server_version.dart';
import 'package:bambuddy_mobile/core/api/server_version_service.dart';
import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/core/models/spool_label.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';

/// The label route's `fields`, `format` and `dpi` (server #2981), against the
/// real server: what a new one does with them, and that an old one — which the
/// app also talks to — takes them without a word and answers a PDF.
void main() {
  group('label options contract', skip: contractSkipReason, () {
    late Dio dio;
    late NativeInventorySource source;
    late bool hasOptions;
    final spoolIds = <int>[];
    final stamp = DateTime.now().millisecondsSinceEpoch;

    setUpAll(() async {
      dio = await authenticatedDio();
      source = NativeInventorySource(dio);
      final version = await ServerVersionService(dio).current();
      hasOptions = version!.supports(ServerFeature.labelFields);
      for (var i = 0; i < 2; i++) {
        final spool = await source.createSpool(
          SpoolDraft(
            material: 'PLA',
            brand: 'Labels $stamp',
            colorName: 'Teal $i',
            labelWeight: 1000,
            // A line is only drawn when the spool has something to put in it.
            note: 'Contract note',
          ),
        );
        spoolIds.add(spool.id);
      }
    });

    tearDownAll(() async {
      final quiet = Options(validateStatus: (_) => true);
      for (final id in spoolIds) {
        await dio.delete<dynamic>(Endpoints.inventorySpool(id), options: quiet);
      }
    });

    Future<Uint8List> render({
      List<int>? ids,
      SpoolLabelTemplate template = SpoolLabelTemplate.box62x29,
      Set<SpoolLabelField>? fields,
      SpoolLabelFormat format = SpoolLabelFormat.pdf,
      int dpi = 300,
    }) => source.renderLabels(
      SpoolLabelRequest(
        spoolIds: ids ?? [spoolIds.first],
        template: template,
        fields: fields,
        format: format,
        dpi: dpi,
      ),
    );

    /// PNG header: signature, then the IHDR chunk, whose first two fields are
    /// the width and the height.
    ({int width, int height}) pngSize(Uint8List png) {
      final header = ByteData.sublistView(png, 16, 24);
      return (width: header.getUint32(0), height: header.getUint32(4));
    }

    test('a default request is a PDF on every server', () async {
      final pdf = await render();
      expect(SpoolLabelFile.of(pdf), SpoolLabelFile.pdf);
    });

    test('a new server answers a PNG at the asked resolution', () async {
      if (!hasOptions) {
        markTestSkipped('server predates #2981');
        return;
      }
      final low = pngSize(await render(format: SpoolLabelFormat.png, dpi: 203));
      final high = pngSize(
        await render(format: SpoolLabelFormat.png, dpi: 600),
      );

      // Same label, three times the dots per inch: the picture grows with it.
      expect(high.width / low.width, closeTo(600 / 203, 0.1));
      // And it is the 62 x 29 mm stock, whatever the resolution.
      expect(low.width / low.height, closeTo(62 / 29, 0.05));
    });

    test('several labels come as a ZIP named after the spools', () async {
      if (!hasOptions) {
        markTestSkipped('server predates #2981');
        return;
      }
      final zip = await render(ids: spoolIds, format: SpoolLabelFormat.png);

      expect(SpoolLabelFile.of(zip), SpoolLabelFile.zip);
      // Stored, not deflated, so the member names are readable as they are.
      final text = latin1.decode(zip);
      for (final id in spoolIds) {
        expect(text, contains('label-$id.png'));
      }
    });

    test('the chosen lines change what is drawn', () async {
      if (!hasOptions) {
        markTestSkipped('server predates #2981');
        return;
      }
      Future<Uint8List> png(Set<SpoolLabelField>? fields) =>
          render(format: SpoolLabelFormat.png, fields: fields);

      final defaults = await png(null);
      // A PNG is the same bytes every time, or the comparison below proves
      // nothing.
      expect(await png(null), defaults);
      expect(await png(SpoolLabelField.defaults), defaults);

      expect(await png({SpoolLabelField.qr}), isNot(defaults));
      expect(
        await png({...SpoolLabelField.defaults, SpoolLabelField.note}),
        isNot(defaults),
      );
    });

    test('no lines at all is accepted, not refused', () async {
      // An empty `fields` is a valid choice on the wire: "none of them".
      final pdf = await render(fields: const {});
      expect(SpoolLabelFile.of(pdf), SpoolLabelFile.pdf);
    });

    test('an older server answers a PDF to a PNG request', () async {
      if (hasOptions) {
        markTestSkipped('server has #2981');
        return;
      }
      // The silent drop the version gate exists for — and the reason the app
      // checks the bytes against the format it asked for.
      await expectLater(
        render(format: SpoolLabelFormat.png),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            AppErrorCode.malformedResponse,
          ),
        ),
      );
      final raw = await dio.post<List<int>>(
        Endpoints.inventoryLabels,
        data: SpoolLabelRequest(
          spoolIds: [spoolIds.first],
          template: SpoolLabelTemplate.box62x29,
          format: SpoolLabelFormat.png,
        ).toJson(),
        options: Options(responseType: ResponseType.bytes),
      );
      expect(
        SpoolLabelFile.of(Uint8List.fromList(raw.data!)),
        SpoolLabelFile.pdf,
      );
    });
  });
}
