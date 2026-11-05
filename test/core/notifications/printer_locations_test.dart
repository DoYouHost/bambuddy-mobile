import 'dart:async';

import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/notifications/printer_locations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const printers = [
    Printer(id: 1, name: 'X1C', location: 'Garage'),
    Printer(id: 2, name: 'P1S', location: ''),
    Printer(id: 3, name: 'A1'),
  ];

  test('answers from the loaded list', () async {
    final locations = PrinterLocations(() async => printers);
    await locations.load();
    expect(locations.of(1), 'Garage');
  });

  test('an empty or missing location is none', () async {
    final locations = PrinterLocations(() async => printers);
    await locations.load();
    expect(locations.of(2), isNull);
    expect(locations.of(3), isNull);
  });

  test('a printer it does not know yet answers null and asks again', () async {
    var calls = 0;
    final locations = PrinterLocations(() async {
      calls++;
      return calls == 1
          ? printers
          : [...printers, const Printer(id: 4, name: 'H2D', location: 'Lab')];
    });
    await locations.load();
    expect(locations.of(4), isNull, reason: 'never waits for the network');
    await Future<void>.delayed(Duration.zero);
    expect(calls, 2);
    expect(locations.of(4), 'Lab');
  });

  test('one request at a time', () async {
    var calls = 0;
    final gate = Completer<List<Printer>>();
    final locations = PrinterLocations(() {
      calls++;
      return gate.future;
    });
    final first = locations.load();
    locations.of(1);
    locations.of(2);
    gate.complete(printers);
    await first;
    expect(calls, 1);
  });

  test('a refusal leaves it unknown and does not throw', () async {
    final locations = PrinterLocations(
      () async => throw const AuthException(AppErrorCode.forbidden),
    );
    await locations.load();
    expect(locations.of(1), isNull);
  });

  test('a bug is not swallowed', () async {
    final locations = PrinterLocations(() async => throw StateError('bug'));
    await expectLater(locations.load(), throwsStateError);
  });
}
