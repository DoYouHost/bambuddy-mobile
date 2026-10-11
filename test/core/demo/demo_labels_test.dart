import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:app_util/app_util.dart';
import 'package:bambuddy_mobile/core/api/server_version.dart';
import 'package:bambuddy_mobile/core/demo/demo_backend.dart';
import 'package:bambuddy_mobile/core/demo/demo_labels.dart';
import 'package:bambuddy_mobile/core/models/spool_label.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// The demo's `POST /inventory/labels`: what each option of the label sheet
/// turns into, checked on the files themselves — a PDF is read as text, a PNG
/// is decoded by the engine, a ZIP is walked member by member.
void main() {
  final backend = DemoBackend.instance;

  DemoResult post(Map<String, dynamic> body) => backend.handle(
    'POST',
    Uri.parse('http://demo/api/v1/inventory/labels'),
    body,
  );

  Uint8List bytesOf(DemoResult r) {
    expect(r.status, 200, reason: '${r.body}');
    return (r.body! as DemoFile).bytes;
  }

  Map<String, dynamic> request({
    List<int> ids = const [1],
    String template = 'box_62x29',
    Map<String, dynamic> extra = const {},
  }) => {'spool_ids': ids, 'template': template, ...extra};

  int pages(Uint8List pdf) =>
      RegExp('/Type /Page ').allMatches(latin1.decode(pdf)).length;

  /// Decoded by the engine, which checks the zlib stream and every chunk's CRC.
  Future<({int width, int height})> decode(
    WidgetTester tester,
    Uint8List png,
  ) async {
    final size = await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(png);
      final frame = await codec.getNextFrame();
      return (width: frame.image.width, height: frame.image.height);
    });
    return size!;
  }

  /// The members of a stored ZIP, read from its central directory.
  Map<String, Uint8List> unzip(Uint8List zip) {
    final data = ByteData.sublistView(zip);
    final end = zip.length - 22;
    expect(data.getUint32(end, Endian.little), 0x06054B50);
    final count = data.getUint16(end + 10, Endian.little);
    var at = data.getUint32(end + 16, Endian.little);
    final members = <String, Uint8List>{};
    for (var i = 0; i < count; i++) {
      expect(data.getUint32(at, Endian.little), 0x02014B50);
      final crc = data.getUint32(at + 16, Endian.little);
      final size = data.getUint32(at + 24, Endian.little);
      final nameLength = data.getUint16(at + 28, Endian.little);
      final local = data.getUint32(at + 42, Endian.little);
      final name = latin1.decode(zip.sublist(at + 46, at + 46 + nameLength));
      expect(data.getUint32(local, Endian.little), 0x04034B50);
      final start = local + 30 + data.getUint16(local + 26, Endian.little);
      final member = zip.sublist(start, start + size);
      expect(demoCrc32(member), crc, reason: '$name is not what its CRC says');
      members[name] = member;
      at += 46 + nameLength;
    }
    return members;
  }

  test('the demo\'s version never hides a feature the demo serves', () {
    // The sheet shows the lines, PNG and dpi only to a server that has them,
    // and the version is what says so — an invented one that fell short would
    // hide everything this file implements.
    final reply = backend.handle(
      'GET',
      Uri.parse('http://demo/api/v1/updates/version'),
      null,
    );
    final version = ServerVersion.tryParse(
      (reply.body! as Map<String, dynamic>)['version'] as String?,
    )!;
    for (final feature in ServerFeature.values) {
      expect(version.supports(feature), isTrue, reason: '$feature');
    }
  });

  test('the CRC is the one PNG and ZIP define', () {
    expect(demoCrc32(ascii.encode('123456789')), 0xCBF43926);
  });

  group('PDF', () {
    test('a roll is a page of its own size per spool', () {
      final pdf = bytesOf(post(request(ids: [1, 2, 3])));
      expect(SpoolLabelFile.of(pdf), SpoolLabelFile.pdf);
      expect(pages(pdf), 3);
      // 62 x 29 mm in points.
      expect(latin1.decode(pdf), contains('/MediaBox [0 0 175.75 82.20]'));
    });

    test('a sheet starts at the slot it was asked to', () {
      // 21 slots on an L7160: from slot 20 the third label spills to page 2.
      final pdf = bytesOf(
        post(
          request(
            ids: [1, 2, 3],
            template: 'avery_l7160',
            extra: {'starting_position': 20},
          ),
        ),
      );
      expect(pages(pdf), 2);
      expect(
        pages(bytesOf(post(request(ids: [1, 2, 3], template: 'avery_l7160')))),
        1,
      );
    });

    test(
      'the last slot of a sheet is the last, and the next label is a page',
      () {
        int sheetPages(int spools, int start) => pages(
          bytesOf(
            post(
              request(
                ids: [for (var i = 0; i < spools; i++) 1],
                template: 'avery_l7160',
                extra: {'starting_position': start},
              ),
            ),
          ),
        );

        // 21 slots: the 21st is the last of page 1, the next one opens page 2.
        expect(sheetPages(1, 21), 1);
        expect(sheetPages(2, 21), 2);
        expect(sheetPages(21, 1), 1);
        expect(sheetPages(22, 1), 2);
      },
    );

    test('the lines are the spool\'s', () {
      final text = latin1.decode(bytesOf(post(request())));
      expect(text, contains('(Black) Tj'));
      expect(text, contains('(PLA Basic) Tj'));
      expect(text, contains('(#1) Tj'));
    });

    test('a line not asked for is not on the label', () {
      final text = latin1.decode(
        bytesOf(
          post(
            request(
              extra: {
                'fields': ['name', 'spool_id'],
              },
            ),
          ),
        ),
      );
      expect(text, contains('(Black) Tj'));
      expect(text, isNot(contains('(PLA Basic) Tj')));
      expect(text, isNot(contains('Shelf A')));
    });

    test('lines that do not fit give way before the spool id does', () {
      final text = latin1.decode(
        bytesOf(
          post(
            request(
              extra: {
                'fields': [for (final f in SpoolLabelField.values) f.wire],
              },
            ),
          ),
        ),
      );
      expect(text, contains('(#1) Tj'));
      // A 29 mm label has room for six lines.
      expect(RegExp(r'\) Tj').allMatches(text).length, lessThanOrEqualTo(6));
    });

    test('a note and a material number can be drawn', () {
      final text = latin1.decode(
        bytesOf(
          post(
            request(
              extra: {
                'fields': ['name', 'note', 'material_number', 'spool_id'],
              },
            ),
          ),
        ),
      );
      expect(text, contains('(Dry box 2) Tj'));
      expect(text, contains('(No. 15) Tj'));
    });

    test('monochrome leaves the swatch out', () {
      final colour = latin1.decode(bytesOf(post(request())));
      final mono = latin1.decode(
        bytesOf(post(request(extra: {'monochrome': true}))),
      );
      // The swatch is the one rectangle that is not black.
      expect(
        RegExp(r'\n0\.00 0\.00 0\.00 rg [^\n]* re f').allMatches(mono).length,
        greaterThan(0),
      );
      expect(mono.length, lessThan(colour.length));
    });
  });

  group('PNG', () {
    testWidgets('is as large as the stock at that resolution', (tester) async {
      Future<({int width, int height})> size(int dpi) async => decode(
        tester,
        bytesOf(post(request(extra: {'format': 'png', 'dpi': dpi}))),
      );

      final low = await size(203);
      final high = await size(600);
      expect(low.width, (62 / 25.4 * 203).round());
      expect(low.height, (29 / 25.4 * 203).round());
      expect(high.width / low.width, closeTo(600 / 203, 0.01));
    });

    test('is the same bytes every time, and other bytes for other lines', () {
      Uint8List png([Map<String, dynamic> extra = const {}]) =>
          bytesOf(post(request(extra: {'format': 'png', ...extra})));

      expect(png(), png());
      expect(
        png({
          'fields': ['qr'],
        }),
        isNot(png()),
      );
      expect(png({'monochrome': true}), isNot(png()));
    });

    testWidgets('several labels are a ZIP of PNGs named after the spools', (
      tester,
    ) async {
      final zip = bytesOf(
        post(request(ids: [1, 2], extra: {'format': 'png', 'dpi': 203})),
      );
      expect(SpoolLabelFile.of(zip), SpoolLabelFile.zip);

      final members = unzip(zip);
      expect(members.keys, ['label-1.png', 'label-2.png']);
      for (final png in members.values) {
        expect((await decode(tester, png)).width, (62 / 25.4 * 203).round());
      }
    });

    test('the pages of a sheet are numbered', () {
      final zip = bytesOf(
        post(
          request(
            ids: [1, 2, 3],
            template: 'avery_5160',
            extra: {'format': 'png', 'starting_position': 29},
          ),
        ),
      );
      expect(unzip(zip).keys, ['sheet-1.png', 'sheet-2.png']);
    });
  });

  group('refusals, as the server words them', () {
    test('a spool that is not there is a 404', () {
      final r = post(request(ids: [1, 9999]));
      expect(r.status, 404);
      expect('${r.body}', contains('9999'));
    });

    test('a position on a roll, or past a sheet, is a 422', () {
      expect(post(request(extra: {'starting_position': 2})).status, 422);
      expect(
        post(
          request(template: 'avery_l7160', extra: {'starting_position': 22}),
        ).status,
        422,
      );
    });

    test('an unknown field, resolution, template or no spools is a 422', () {
      expect(
        post(
          request(
            extra: {
              'fields': ['sparkle'],
            },
          ),
        ).status,
        422,
      );
      expect(post(request(extra: {'format': 'png', 'dpi': 72})).status, 422);
      expect(post(request(template: 'box_1x1')).status, 422);
      expect(post(request(ids: const [])).status, 422);
    });
  });

  testWidgets('the app takes what the demo sends, in both formats', (
    tester,
  ) async {
    // Through the same source, and the same check on the bytes, as the real
    // server's answer — which is what keeps the demo honest about the format.
    final dio = Dio(BaseOptions(baseUrl: 'http://demo'))
      ..httpClientAdapter = DemoHttpClientAdapter(backend.handle);
    final source = NativeInventorySource(dio);

    // The adapter waits a moment, like a network would, on a real clock.
    await tester.runAsync(() async {
      final pdf = await source.renderLabels(
        const SpoolLabelRequest(
          spoolIds: [1],
          template: SpoolLabelTemplate.box62x29,
        ),
      );
      expect(SpoolLabelFile.of(pdf), SpoolLabelFile.pdf);

      final png = await source.renderLabels(
        const SpoolLabelRequest(
          spoolIds: [1],
          template: SpoolLabelTemplate.box62x29,
          format: SpoolLabelFormat.png,
          dpi: 203,
          fields: {SpoolLabelField.qr},
        ),
      );
      expect(SpoolLabelFile.of(png), SpoolLabelFile.png);
    });
  });
}
