import 'dart:convert';
import 'dart:io' show ZLibEncoder;
import 'dart:math' as math;
import 'dart:typed_data';

import '../models/spool_label.dart';

/// Labels for the demo backend: what `POST /inventory/labels` would answer, drawn
/// here so the demo can show every label option — the lines, monochrome, a
/// part-used sheet, PDF and PNG at a chosen resolution, a ZIP of several.
///
/// One layout is painted onto two canvases, a PDF page and a raster, so the two
/// formats agree on what is on a label. The QR is a stand-in with the shape of
/// one: nothing scans it, and the demo has no server for it to point at.

/// One spool, as much of it as a label carries.
class DemoLabelSpool {
  const DemoLabelSpool({
    required this.id,
    required this.material,
    this.subtype,
    this.brand,
    this.colorName,
    this.rgba,
    this.location,
    this.materialNumber,
    this.tempMin,
    this.tempMax,
    this.labelWeight,
    this.note,
    this.added,
  });

  factory DemoLabelSpool.fromJson(Map<String, dynamic> json) => DemoLabelSpool(
    id: (json['id'] as num).toInt(),
    material: json['material'] as String? ?? '',
    subtype: json['subtype'] as String?,
    brand: json['brand'] as String?,
    colorName: json['color_name'] as String?,
    rgba: json['rgba'] as String?,
    location: json['storage_location'] as String?,
    materialNumber: json['material_number'] as String?,
    tempMin: (json['nozzle_temp_min'] as num?)?.toInt(),
    tempMax: (json['nozzle_temp_max'] as num?)?.toInt(),
    labelWeight: (json['label_weight'] as num?)?.toInt(),
    note: json['note'] as String?,
    added: DateTime.tryParse('${json['created_at'] ?? ''}'),
  );

  final int id;
  final String material;
  final String? subtype;
  final String? brand;
  final String? colorName;

  /// `RRGGBBAA`, no `#` — the server's own spelling.
  final String? rgba;
  final String? location;
  final String? materialNumber;
  final int? tempMin;
  final int? tempMax;
  final int? labelWeight;
  final String? note;
  final DateTime? added;

  int get _rgb {
    final hex = rgba;
    if (hex == null || hex.length < 6) return 0x888888;
    return int.tryParse(hex.substring(0, 6), radix: 16) ?? 0x888888;
  }
}

/// A rendered answer and the type it is served as.
typedef DemoLabelFile = ({Uint8List bytes, String contentType});

/// The file for [spools] on [template], as `_render_response` in the server's
/// `labels.py` would send it: a PDF, or one PNG, or a ZIP of PNGs.
///
/// [fields] are the server's `LabelField` names. [startingPosition] counts
/// slots of a sheet from 1 and leaves the ones before it blank.
DemoLabelFile renderDemoLabels({
  required List<DemoLabelSpool> spools,
  required SpoolLabelTemplate template,
  required Set<String> fields,
  bool monochrome = false,
  int startingPosition = 1,
  bool png = false,
  int dpi = 300,
}) {
  final g = _Geometry.of(template);
  final pages = <List<({int slot, DemoLabelSpool spool})>>[];
  final offset = g.sheet == null ? 0 : startingPosition - 1;
  final perPage = g.sheet == null ? 1 : g.columns * g.rows;
  for (var i = 0; i < spools.length; i++) {
    final position = offset + i;
    final page = position ~/ perPage;
    while (pages.length <= page) {
      pages.add([]);
    }
    pages[page].add((slot: position % perPage, spool: spools[i]));
  }

  void paintPage(_Canvas canvas, List<({int slot, DemoLabelSpool spool})> p) {
    for (final entry in p) {
      final col = entry.slot % g.columns;
      final row = entry.slot ~/ g.columns;
      _paintLabel(
        canvas,
        g.originX + col * (g.labelW + g.gapX),
        g.originY + row * (g.labelH + g.gapY),
        g.labelW,
        g.labelH,
        entry.spool,
        fields,
        monochrome,
      );
    }
  }

  if (!png) {
    final pdf = _PdfBuilder(g.pageW, g.pageH);
    for (final p in pages) {
      paintPage(pdf.newPage(), p);
    }
    return (bytes: pdf.build(), contentType: 'application/pdf');
  }

  final images = <Uint8List>[];
  for (final p in pages) {
    final raster = _Raster(g.pageW, g.pageH, dpi);
    paintPage(raster, p);
    images.add(raster.toPng());
  }
  if (images.length == 1) {
    return (bytes: images.single, contentType: 'image/png');
  }
  // A roll has a page per spool and is named after it; a sheet's are numbered.
  final names = g.sheet == null
      ? [for (final s in spools) 'label-${s.id}.png']
      : [for (var n = 1; n <= images.length; n++) 'sheet-$n.png'];
  return (bytes: _zip(names, images), contentType: 'application/zip');
}

class _Geometry {
  _Geometry({
    required this.pageW,
    required this.pageH,
    required this.labelW,
    required this.labelH,
    this.columns = 1,
    this.rows = 1,
    this.sheet,
  }) : gapX = columns > 1 ? 2.5 : 0,
       gapY = 0;

  factory _Geometry.of(SpoolLabelTemplate t) {
    final sheet = t.sheet;
    if (sheet != null) {
      // L7160 is A4, 5160 is US Letter; the grid sits centred on the page.
      final a4 = t == SpoolLabelTemplate.averyL7160;
      final g = _Geometry(
        pageW: a4 ? 210 : 215.9,
        pageH: a4 ? 297 : 279.4,
        labelW: sheet.widthMm,
        labelH: sheet.heightMm,
        columns: sheet.columns,
        rows: sheet.rows,
        sheet: sheet,
      );
      return g;
    }
    final (w, h) = switch (t) {
      SpoolLabelTemplate.amsHolderSmall => (74.0, 33.0),
      SpoolLabelTemplate.amsHolderLarge => (75.0, 55.0),
      SpoolLabelTemplate.box40x30 => (40.0, 30.0),
      _ => (62.0, 29.0),
    };
    return _Geometry(pageW: w, pageH: h, labelW: w, labelH: h);
  }

  final double pageW;
  final double pageH;
  final double labelW;
  final double labelH;
  final int columns;
  final int rows;
  final double gapX;
  final double gapY;
  final ({int columns, int rows, double widthMm, double heightMm})? sheet;

  double get originX => (pageW - columns * labelW - (columns - 1) * gapX) / 2;
  double get originY => (pageH - rows * labelH - (rows - 1) * gapY) / 2;
}

/// The lines a label can carry, in the order they read down the label.
const _lineOrder = [
  'name',
  'material',
  'brand',
  'hex',
  'location',
  'material_number',
  'temps',
  'weight',
  'note',
  'added',
  'spool_id',
];

String? _lineText(String field, DemoLabelSpool s) {
  String? nonEmpty(String? v) =>
      v == null || v.trim().isEmpty ? null : v.trim();
  return switch (field) {
    'name' =>
      nonEmpty(s.colorName) ?? nonEmpty('${s.brand ?? ''} ${s.material}'),
    'material' => nonEmpty('${s.material} ${s.subtype ?? ''}'),
    'brand' => nonEmpty(s.brand),
    'hex' => '#${s._rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}',
    'location' => nonEmpty(s.location),
    'material_number' =>
      nonEmpty(s.materialNumber) == null ? null : 'No. ${s.materialNumber}',
    'temps' =>
      s.tempMin == null || s.tempMax == null
          ? null
          : '${s.tempMin}-${s.tempMax} C',
    'weight' => s.labelWeight == null ? null : '${s.labelWeight} g',
    'note' => nonEmpty(s.note),
    'added' => s.added?.toIso8601String().substring(0, 10),
    'spool_id' => '#${s.id}',
    _ => null,
  };
}

/// Average advance of a character, as a share of its size — what both canvases
/// are laid out against, so a line that fits one fits the other.
const _advance = 0.55;

void _paintLabel(
  _Canvas c,
  double x,
  double y,
  double w,
  double h,
  DemoLabelSpool s,
  Set<String> fields,
  bool monochrome,
) {
  const pad = 1.8;
  final qr = fields.contains('qr') ? math.min(h - 2 * pad, w * 0.38) : 0.0;
  var textX = x + pad;
  if (!monochrome) {
    // The colour swatch; a black-and-white printer would print it as grey.
    c.rect(x + pad, y + pad, 3.0, h - 2 * pad, rgb: s._rgb);
    textX += 3.0 + 1.6;
  }
  final maxW = x + w - pad - (qr > 0 ? qr + 1.5 : 0) - textX;

  final size = (h * 0.11).clamp(2.2, 4.2);
  final lineH = size * 1.25;
  final capacity = ((h - 2 * pad) / lineH).floor();

  final lines = <(String field, String text)>[
    for (final f in _lineOrder)
      if (fields.contains(f))
        if (_lineText(f, s) case final t?) (f, t),
  ];
  // A line that does not fit is left out, never printed over the spool ID: the
  // ID is the last line, so the ones before it give way first.
  while (lines.length > capacity && lines.length > 1) {
    final drop = lines.length >= 2 && lines.last.$1 == 'spool_id'
        ? lines.length - 2
        : lines.length - 1;
    lines.removeAt(drop);
  }

  final maxChars = math.max(1, (maxW / (size * _advance)).floor());
  var ty = y + pad;
  for (var i = 0; i < lines.length; i++) {
    var text = lines[i].$2;
    if (text.length > maxChars) text = '${text.substring(0, maxChars - 1)}.';
    c.text(textX, ty, text, sizeMm: size, bold: i == 0);
    ty += lineH;
  }

  if (qr > 0) {
    _paintQr(c, x + w - pad - qr, y + (h - qr) / 2, qr, s.id);
  }
}

/// The look of a QR code — three finder squares and a scatter of modules, fixed
/// by the spool id — and not one: nothing reads it.
void _paintQr(_Canvas c, double x, double y, double size, int seed) {
  const n = 21;
  final m = size / n;
  bool finder(int r, int col) {
    for (final (fr, fc) in const [(0, 0), (0, n - 7), (n - 7, 0)]) {
      final dr = r - fr;
      final dc = col - fc;
      if (dr < 0 || dr > 6 || dc < 0 || dc > 6) continue;
      final ring = math.max((dr - 3).abs(), (dc - 3).abs());
      return ring != 2;
    }
    return false;
  }

  bool inFinder(int r, int col) =>
      (r < 8 && col < 8) || (r < 8 && col >= n - 8) || (r >= n - 8 && col < 8);

  for (var r = 0; r < n; r++) {
    for (var col = 0; col < n; col++) {
      final on = inFinder(r, col)
          ? finder(r, col)
          : (seed * 31 + r * 17 + col * 13 + r * col) % 3 == 0;
      if (on) c.rect(x + col * m, y + r * m, m, m, rgb: 0x000000);
    }
  }
}

abstract class _Canvas {
  /// Filled rectangle; coordinates are millimetres from the page's top left.
  void rect(double x, double y, double w, double h, {required int rgb});

  /// [y] is the top of the capitals.
  void text(
    double x,
    double y,
    String text, {
    required double sizeMm,
    bool bold = false,
  });
}

// --- PDF ---

class _PdfBuilder {
  _PdfBuilder(this.pageW, this.pageH);

  final double pageW;
  final double pageH;
  final _pages = <_PdfPage>[];

  _Canvas newPage() {
    final page = _PdfPage(pageH);
    _pages.add(page);
    return page;
  }

  static double _pt(double mm) => mm * 72 / 25.4;

  Uint8List build() {
    // 1 catalog, 2 pages, 3 and 4 the fonts, then a page and its content each.
    final objects = <String>[];
    final kids = [for (var i = 0; i < _pages.length; i++) '${5 + i * 2} 0 R'];
    objects.add('<< /Type /Catalog /Pages 2 0 R >>');
    objects.add(
      '<< /Type /Pages /Count ${_pages.length} /Kids [${kids.join(' ')}] >>',
    );
    objects.add(
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>',
    );
    objects.add(
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>',
    );
    for (var i = 0; i < _pages.length; i++) {
      final content = _pages[i].content.toString();
      objects.add(
        '<< /Type /Page /Parent 2 0 R '
        '/MediaBox [0 0 ${_pt(pageW).toStringAsFixed(2)} ${_pt(pageH).toStringAsFixed(2)}] '
        '/Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> '
        '/Contents ${6 + i * 2} 0 R >>',
      );
      objects.add(
        '<< /Length ${latin1.encode(content).length} >>\nstream\n$content\nendstream',
      );
    }

    final out = BytesBuilder();
    final offsets = <int>[];
    void write(String s) => out.add(latin1.encode(s));
    write('%PDF-1.4\n');
    for (var i = 0; i < objects.length; i++) {
      offsets.add(out.length);
      write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
    }
    final xref = out.length;
    write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
    for (final o in offsets) {
      write('${o.toString().padLeft(10, '0')} 00000 n \n');
    }
    write(
      'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n',
    );
    return out.toBytes();
  }
}

class _PdfPage implements _Canvas {
  _PdfPage(this.pageH);

  final double pageH;
  final content = StringBuffer();

  static String _n(double v) => v.toStringAsFixed(2);

  static String _color(int rgb) =>
      '${_n(((rgb >> 16) & 0xFF) / 255)} ${_n(((rgb >> 8) & 0xFF) / 255)} ${_n((rgb & 0xFF) / 255)}';

  @override
  void rect(double x, double y, double w, double h, {required int rgb}) {
    content.writeln(
      '${_color(rgb)} rg ${_n(_PdfBuilder._pt(x))} '
      '${_n(_PdfBuilder._pt(pageH - y - h))} ${_n(_PdfBuilder._pt(w))} '
      '${_n(_PdfBuilder._pt(h))} re f',
    );
  }

  @override
  void text(
    double x,
    double y,
    String text, {
    required double sizeMm,
    bool bold = false,
  }) {
    // WinAnsi reaches Latin-1; anything past it would be a wrong glyph.
    final safe = String.fromCharCodes([
      for (final u in text.codeUnits) u > 255 ? 0x3F : u,
    ]).replaceAll('\\', '\\\\').replaceAll('(', '\\(').replaceAll(')', '\\)');
    // `y` is the top of the capitals; Helvetica's cap height is ~0.72 em.
    final baseline = pageH - (y + sizeMm * 0.72);
    content.writeln(
      'BT /${bold ? 'F2' : 'F1'} ${_n(_PdfBuilder._pt(sizeMm))} Tf '
      '0 0 0 rg ${_n(_PdfBuilder._pt(x))} ${_n(_PdfBuilder._pt(baseline))} Td '
      '($safe) Tj ET',
    );
  }
}

// --- Raster / PNG ---

class _Raster implements _Canvas {
  _Raster(double pageWmm, double pageHmm, this.dpi)
    : width = (pageWmm / 25.4 * dpi).round(),
      height = (pageHmm / 25.4 * dpi).round() {
    pixels = Uint8List(width * height * 3)
      ..fillRange(0, width * height * 3, 255);
  }

  final int dpi;
  final int width;
  final int height;
  late final Uint8List pixels;

  int _px(double mm) => (mm / 25.4 * dpi).round();

  void _fill(int x0, int y0, int x1, int y1, int rgb) {
    final r = (rgb >> 16) & 0xFF, g = (rgb >> 8) & 0xFF, b = rgb & 0xFF;
    for (var y = math.max(0, y0); y < math.min(height, y1); y++) {
      for (var x = math.max(0, x0); x < math.min(width, x1); x++) {
        final o = (y * width + x) * 3;
        pixels[o] = r;
        pixels[o + 1] = g;
        pixels[o + 2] = b;
      }
    }
  }

  @override
  void rect(double x, double y, double w, double h, {required int rgb}) {
    // Both edges are rounded, not the size: modules laid edge to edge would
    // otherwise leave a dot of white between them.
    final x0 = _px(x), y0 = _px(y);
    // At least a dot, so a QR module stays visible at 203 dpi.
    _fill(
      x0,
      y0,
      math.max(x0 + 1, _px(x + w)),
      math.max(y0 + 1, _px(y + h)),
      rgb,
    );
  }

  @override
  void text(
    double x,
    double y,
    String text, {
    required double sizeMm,
    bool bold = false,
  }) {
    final scale = math.max(1, (_px(sizeMm) * _advance / 6).round());
    var cx = _px(x);
    final cy = _px(y);
    for (final ch in text.toUpperCase().split('')) {
      final glyph = _font[ch] ?? _font['?']!;
      for (var row = 0; row < 7; row++) {
        for (var col = 0; col < 5; col++) {
          if (glyph[row] & (1 << (4 - col)) == 0) continue;
          final px = cx + col * scale;
          final py = cy + row * scale;
          _fill(
            px,
            py,
            px + scale + (bold ? math.max(1, scale ~/ 2) : 0),
            py + scale,
            0,
          );
        }
      }
      cx += 6 * scale;
    }
  }

  Uint8List toPng() => demoPng(width, height, pixels);
}

/// An RGB image ([pixels] row-major, three bytes each) as an unfiltered PNG.
Uint8List demoPng(int width, int height, Uint8List pixels) {
  final raw = BytesBuilder();
  for (var y = 0; y < height; y++) {
    raw.addByte(0); // filter: none
    raw.add(Uint8List.sublistView(pixels, y * width * 3, (y + 1) * width * 3));
  }
  final ihdr = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, 2); // colour type: RGB
  final out = BytesBuilder()
    ..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  void chunk(String type, List<int> data) {
    final body = [...latin1.encode(type), ...data];
    final length = ByteData(4)..setUint32(0, data.length);
    final crc = ByteData(4)..setUint32(0, demoCrc32(body));
    out
      ..add(length.buffer.asUint8List())
      ..add(body)
      ..add(crc.buffer.asUint8List());
  }

  chunk('IHDR', ihdr.buffer.asUint8List());
  chunk('IDAT', ZLibEncoder().convert(raw.toBytes()));
  chunk('IEND', const []);
  return out.toBytes();
}

// --- ZIP, stored ---

final _crcTable = () {
  final table = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = c & 1 == 1 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    table[n] = c;
  }
  return table;
}();

/// CRC-32 as PNG and ZIP both define it.
int demoCrc32(List<int> data) {
  var c = 0xFFFFFFFF;
  for (final b in data) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}

/// Members stored, not deflated — a PNG is compressed already, which is also
/// what the server does.
Uint8List _zip(List<String> names, List<Uint8List> files) {
  final out = BytesBuilder();
  final central = BytesBuilder();
  for (var i = 0; i < names.length; i++) {
    final name = latin1.encode(names[i]);
    final crc = demoCrc32(files[i]);
    final offset = out.length;
    final local = ByteData(30)
      ..setUint32(0, 0x04034B50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint32(14, crc, Endian.little)
      ..setUint32(18, files[i].length, Endian.little)
      ..setUint32(22, files[i].length, Endian.little)
      ..setUint16(26, name.length, Endian.little);
    out
      ..add(local.buffer.asUint8List())
      ..add(name)
      ..add(files[i]);

    final entry = ByteData(46)
      ..setUint32(0, 0x02014B50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, 20, Endian.little)
      ..setUint32(16, crc, Endian.little)
      ..setUint32(20, files[i].length, Endian.little)
      ..setUint32(24, files[i].length, Endian.little)
      ..setUint16(28, name.length, Endian.little)
      ..setUint32(42, offset, Endian.little);
    central
      ..add(entry.buffer.asUint8List())
      ..add(name);
  }
  final centralOffset = out.length;
  final centralBytes = central.toBytes();
  out.add(centralBytes);
  final end = ByteData(22)
    ..setUint32(0, 0x06054B50, Endian.little)
    ..setUint16(8, names.length, Endian.little)
    ..setUint16(10, names.length, Endian.little)
    ..setUint32(12, centralBytes.length, Endian.little)
    ..setUint32(16, centralOffset, Endian.little);
  out.add(end.buffer.asUint8List());
  return out.toBytes();
}

/// 5 x 7 capitals, digits and the few marks a label uses; one row per byte,
/// the leftmost dot in bit 4.
const _font = <String, List<int>>{
  'A': [0x0E, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11],
  'B': [0x1E, 0x11, 0x11, 0x1E, 0x11, 0x11, 0x1E],
  'C': [0x0E, 0x11, 0x10, 0x10, 0x10, 0x11, 0x0E],
  'D': [0x1E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x1E],
  'E': [0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x1F],
  'F': [0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x10],
  'G': [0x0E, 0x11, 0x10, 0x17, 0x11, 0x11, 0x0F],
  'H': [0x11, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11],
  'I': [0x0E, 0x04, 0x04, 0x04, 0x04, 0x04, 0x0E],
  'J': [0x07, 0x02, 0x02, 0x02, 0x02, 0x12, 0x0C],
  'K': [0x11, 0x12, 0x14, 0x18, 0x14, 0x12, 0x11],
  'L': [0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x1F],
  'M': [0x11, 0x1B, 0x15, 0x15, 0x11, 0x11, 0x11],
  'N': [0x11, 0x11, 0x19, 0x15, 0x13, 0x11, 0x11],
  'O': [0x0E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E],
  'P': [0x1E, 0x11, 0x11, 0x1E, 0x10, 0x10, 0x10],
  'Q': [0x0E, 0x11, 0x11, 0x11, 0x15, 0x12, 0x0D],
  'R': [0x1E, 0x11, 0x11, 0x1E, 0x14, 0x12, 0x11],
  'S': [0x0F, 0x10, 0x10, 0x0E, 0x01, 0x01, 0x1E],
  'T': [0x1F, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04],
  'U': [0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E],
  'V': [0x11, 0x11, 0x11, 0x11, 0x11, 0x0A, 0x04],
  'W': [0x11, 0x11, 0x11, 0x15, 0x15, 0x1B, 0x11],
  'X': [0x11, 0x11, 0x0A, 0x04, 0x0A, 0x11, 0x11],
  'Y': [0x11, 0x11, 0x0A, 0x04, 0x04, 0x04, 0x04],
  'Z': [0x1F, 0x01, 0x02, 0x04, 0x08, 0x10, 0x1F],
  '0': [0x0E, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0E],
  '1': [0x04, 0x0C, 0x04, 0x04, 0x04, 0x04, 0x0E],
  '2': [0x0E, 0x11, 0x01, 0x02, 0x04, 0x08, 0x1F],
  '3': [0x1E, 0x01, 0x01, 0x0E, 0x01, 0x01, 0x1E],
  '4': [0x02, 0x06, 0x0A, 0x12, 0x1F, 0x02, 0x02],
  '5': [0x1F, 0x10, 0x1E, 0x01, 0x01, 0x11, 0x0E],
  '6': [0x06, 0x08, 0x10, 0x1E, 0x11, 0x11, 0x0E],
  '7': [0x1F, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08],
  '8': [0x0E, 0x11, 0x11, 0x0E, 0x11, 0x11, 0x0E],
  '9': [0x0E, 0x11, 0x11, 0x0F, 0x01, 0x02, 0x0C],
  ' ': [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
  '#': [0x0A, 0x0A, 0x1F, 0x0A, 0x1F, 0x0A, 0x0A],
  '-': [0x00, 0x00, 0x00, 0x1F, 0x00, 0x00, 0x00],
  '.': [0x00, 0x00, 0x00, 0x00, 0x00, 0x0C, 0x0C],
  ',': [0x00, 0x00, 0x00, 0x00, 0x0C, 0x04, 0x08],
  ':': [0x00, 0x0C, 0x0C, 0x00, 0x0C, 0x0C, 0x00],
  '/': [0x01, 0x01, 0x02, 0x04, 0x08, 0x10, 0x10],
  '(': [0x02, 0x04, 0x08, 0x08, 0x08, 0x04, 0x02],
  ')': [0x08, 0x04, 0x02, 0x02, 0x02, 0x04, 0x08],
  '+': [0x00, 0x04, 0x04, 0x1F, 0x04, 0x04, 0x00],
  '%': [0x18, 0x19, 0x02, 0x04, 0x08, 0x13, 0x03],
  '?': [0x0E, 0x11, 0x01, 0x02, 0x04, 0x00, 0x04],
};
