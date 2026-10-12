import '../models/filament_requirement.dart';

/// What the print form says a job costs, as the web's mapping panel works it out
/// (`FilamentMapping.tsx::totalCost`): for each filament the plate uses, its grams
/// at the price of the spool on the tray it is mapped to, or at the server's
/// default price where that tray has none.
///
/// This is a preview. The server prices the job itself when it is queued
/// (`print_cost_estimate.py::estimate_queue_source_cost`) and ignores what is sent.
typedef JobCost = ({double total, bool anyPrice});

/// [mapping] is the job's `ams_mapping`: index `slotId - 1` holds the global tray
/// of that filament, or `-1`. [costPerKgByTray] holds the price of the spool each
/// tray carries — only a tray with a priced spool has an entry. Null when there is
/// no mapping to price against, which is every job aimed at "any printer of a model".
JobCost? estimateJobCost({
  required List<FilamentRequirement> requirements,
  required List<int>? mapping,
  required Map<int, double> costPerKgByTray,
  required double defaultCostPerKg,
}) {
  if (mapping == null) return null;
  var total = 0.0;
  for (final f in requirements) {
    if (!f.usedInPlate) continue;
    final index = f.slotId - 1;
    if (index < 0 || index >= mapping.length || mapping[index] < 0) continue;
    final perKg = costPerKgByTray[mapping[index]] ?? defaultCostPerKg;
    if (perKg > 0) total += (f.usedGrams ?? 0) / 1000 * perKg;
  }
  return (
    total: total,
    anyPrice: costPerKgByTray.values.any((price) => price > 0),
  );
}
