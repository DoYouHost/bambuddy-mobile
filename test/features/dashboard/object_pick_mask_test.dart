import 'dart:typed_data';
import 'dart:ui';

import 'package:bambuddy_mobile/features/dashboard/object_pick_mask.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mask pixels in the slicer's encoding: object id in r/g/b, opaque unless the
/// id is 0 — that is how a plate pixel looks in `pick_N.png`.
Uint8List _rgba(int width, int height, int Function(int x, int y) idAt) {
  final bytes = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final id = idAt(x, y);
      final p = (y * width + x) * 4;
      bytes[p] = id & 0xFF;
      bytes[p + 1] = (id >> 8) & 0xFF;
      bytes[p + 2] = (id >> 16) & 0xFF;
      bytes[p + 3] = id == 0 ? 0 : 255;
    }
  }
  return bytes;
}

/// 10×10 plate: object 80 as a 4×3 block, object 300 (an id that only decodes
/// right if the green channel is read) as a 5×5 ring around a hole.
ObjectPickMask _plate() => ObjectPickMask.fromRgba(
  _rgba(10, 10, (x, y) {
    if (x >= 1 && x <= 4 && y >= 1 && y <= 3) return 80;
    final ring = x >= 5 && x <= 9 && y >= 5 && y <= 9;
    final hole = x >= 6 && x <= 8 && y >= 6 && y <= 8;
    return ring && !hole ? 300 : 0;
  }),
  10,
  10,
)!;

void main() {
  const box = Size(100, 100); // 10 logical px per mask pixel.

  test('id obiektu składa się z kanałów r/g/b', () {
    expect(_plate().shapes.keys, containsAll(<int>[80, 300]));
  });

  test('dotknięcie kształtu zwraca jego obiekt, dotknięcie płyty nic', () {
    final mask = _plate();

    expect(mask.idAt(const Offset(25, 25), box), 80);
    expect(mask.idAt(const Offset(55, 55), box), 300);
    // The ring's hole is plate, not the object drawn around it.
    expect(mask.idAt(const Offset(75, 75), box), isNull);
    expect(mask.idAt(const Offset(5, 95), box), isNull);
  });

  test('pasy letterboxa nie trafiają w nic', () {
    final mask = _plate();
    // A mask narrower than its box is centred, so x<50 is the left bar. Without
    // the bounds check it would clamp onto whatever touches the plate's edge.
    expect(mask.idAt(const Offset(10, 25), const Size(200, 100)), isNull);
    expect(mask.idAt(const Offset(75, 25), const Size(200, 100)), 80);
  });

  test('tolerancja ratuje dotknięcie tuż obok, ale nie przebija trafienia', () {
    final mask = _plate();

    // 5 px past the block's left edge — within a finger's slop.
    expect(mask.idAt(const Offset(5, 25), box, tolerance: 8), 80);
    // Far from everything: still nothing, tolerance or not.
    expect(mask.idAt(const Offset(5, 95), box, tolerance: 8), isNull);
    // Inside a shape the tolerance never gets a say.
    expect(mask.idAt(const Offset(55, 55), box, tolerance: 40), 300);
  });

  test('prostokąt: obrys, zasięg etykiety i kotwica pośrodku', () {
    final shape = _plate().shapes[80]!;

    expect(shape.bounds, const Rect.fromLTRB(1, 1, 5, 4));
    expect(shape.labelSpan, 4);
    expect(shape.labelAnchor, const Offset(3, 2.5));
    // One unit segment per border pixel edge: 2×(4+3) around a 4×3 block.
    expect(shape.outline.length, 14 * 4);
  });

  test('pierścień: etykieta ląduje w materiale, nie w dziurze', () {
    final mask = _plate();
    final anchor = mask.shapes[300]!.labelAnchor;

    // Top and bottom edge are equally wide; their midpoint would be the hole.
    expect(mask.idAt(anchor * 10, box), 300);
  });

  test('maska bez obiektów i maska za krótka to brak maski', () {
    expect(ObjectPickMask.fromRgba(_rgba(4, 4, (_, _) => 0), 4, 4), isNull);
    expect(ObjectPickMask.fromRgba(Uint8List(16), 4, 4), isNull);
  });
}
