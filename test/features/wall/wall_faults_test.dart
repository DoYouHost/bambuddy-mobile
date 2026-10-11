import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/features/wall/wall_faults.dart';
import 'package:flutter_test/flutter_test.dart';

PrinterWithStatus _printer(
  int id,
  String name,
  List<HmsError> errors, {
  bool connected = true,
}) => PrinterWithStatus(
  printer: Printer(id: id, name: name),
  status: PrinterStatus(id: id, connected: connected, hmsErrors: errors),
);

HmsError _err(String code, String message) =>
    HmsError(code: code, message: message);

String? _noCatalog(HmsError _) => null;

void main() {
  test('no printers, or none with a fault, is an empty list', () {
    expect(wallFaults(const [], describe: _noCatalog), isEmpty);
    expect(
      wallFaults([_printer(1, 'P1S', const [])], describe: _noCatalog),
      isEmpty,
    );
  });

  test('sorts by HMS level, fatal first', () {
    final faults = wallFaults([
      _printer(1, 'A', [_err('0x30001', 'common')]),
      _printer(2, 'B', [_err('0x10001', 'fatal')]),
      _printer(3, 'C', [_err('0x20001', 'serious')]),
    ], describe: _noCatalog);

    expect([for (final f in faults) f.text], ['fatal', 'serious', 'common']);
  });

  test('breaks a tie on level by printer name', () {
    final faults = wallFaults([
      _printer(1, 'X1C-02', [_err('0x20001', 'b')]),
      _printer(2, 'P1S', [_err('0x20002', 'a')]),
    ], describe: _noCatalog);

    expect([for (final f in faults) f.printer], ['P1S', 'X1C-02']);
  });

  test('puts a fault without a level after every leveled one', () {
    final faults = wallFaults([
      _printer(1, 'A', [_err('0x2001', 'no level')]),
      _printer(2, 'Z', [_err('0x40001', 'info')]),
    ], describe: _noCatalog);

    expect([for (final f in faults) f.text], ['info', 'no level']);
  });

  test('leaves out an offline printer and a fault nobody can name', () {
    final faults = wallFaults([
      _printer(1, 'Gone', [_err('0x10001', 'stale')], connected: false),
      _printer(2, 'Here', [const HmsError(code: '0x10001')]),
    ], describe: _noCatalog);

    expect(faults, isEmpty);
  });

  test('prefers the catalogue text over the server message', () {
    final faults = wallFaults([
      _printer(1, 'A', [_err('0x10001', 'raw')]),
    ], describe: (_) => 'Catalogued');

    expect(faults.single.text, 'Catalogued');
  });
}
