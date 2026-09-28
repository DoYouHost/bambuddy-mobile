import '../../core/models/printer_status.dart';
import '../../core/notifications/hms_catalog.dart';
import '../../data/printers_repository.dart';

/// One active fault on the wall, with the printer it belongs to.
typedef WallFault = ({String printer, HmsError error, String? text});

/// Every active fault across the farm, most severe first, then by printer name
/// (D17). There is no time to sort on: `HmsError` carries none.
///
/// Severity is the HMS level ([HmsError.level]); a fault without one sorts
/// after all that have one. Only faults the printer card would list are here
/// ([displayableHmsErrors]), so an offline printer contributes none.
List<WallFault> wallFaults(
  List<PrinterWithStatus> printers, {
  required String? Function(HmsError) describe,
}) {
  final faults = <WallFault>[
    for (final p in printers)
      for (final e in displayableHmsErrors(p.status, describe: describe))
        (printer: p.printer.name, error: e, text: describe(e) ?? e.message),
  ];
  faults.sort((a, b) {
    final byLevel = (a.error.level ?? 5).compareTo(b.error.level ?? 5);
    return byLevel != 0 ? byLevel : a.printer.compareTo(b.printer);
  });
  return faults;
}
