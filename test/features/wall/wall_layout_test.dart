import 'dart:ui';

import 'package:bambuddy_mobile/features/wall/wall_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The grid area left beside the rail on a landscape phone, and beside the
  // expanded panel on a landscape tablet.
  const phone = Size(744, 342);
  const tablet = Size(930, 752);

  test('one printer, or none, takes a single column', () {
    expect(wallColumns(0, phone), 1);
    expect(wallColumns(1, phone), 1);
  });

  test('an empty area does not divide by zero', () {
    expect(wallColumns(5, Size.zero), 1);
  });

  test('the demo farm of five fills three columns on a phone', () {
    expect(wallColumns(5, phone), 3);
  });

  test('a taller tablet area stacks the same five in two columns', () {
    expect(wallColumns(5, tablet), 2);
  });

  test('two printers sit side by side on a wide, short area', () {
    expect(wallColumns(2, phone), 2);
  });

  test('twelve on a tablet take three columns: 303 px frames against 225', () {
    expect(wallColumns(12, tablet), 3);
  });
}
