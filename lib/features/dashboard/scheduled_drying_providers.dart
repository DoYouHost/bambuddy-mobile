import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ams/drying_presets.dart';
import '../../core/models/scheduled_drying.dart';
import '../../providers.dart';

/// Every drying run the server is holding for later — the whole fleet in one
/// request, not one per printer.
///
/// A card filters it with [scheduledDryingsFor]. The alternative, a
/// `family` keyed by printer, would put a request behind every card on the
/// dashboard for a list that is almost always empty. Not `autoDispose`: the
/// dashboard rebuilds these cards constantly (every status frame), and a
/// provider that died between two builds would refetch each time.
///
/// Refreshed by the dashboard's pull-to-refresh, by opening the drying sheet,
/// and by scheduling or cancelling a run — the row's `waiting_reason` is the
/// only part that drifts on its own, and it explains a wait rather than driving
/// one.
final scheduledDryingsProvider = FutureProvider<List<ScheduledDrying>>(
  (ref) => ref.watch(scheduledDryingRepositoryProvider).list(),
);

/// Whether the drying sheet offers the "later" start modes at all. False on a
/// server without the route, and until the first listing has answered.
final scheduledDryingSupportedProvider = FutureProvider<bool>((ref) async {
  // Waits for the listing rather than racing it: that request is what sets the
  // latch this reads, so asking first would only ever repeat the version
  // table's guess and then never be asked again. A listing that failed for some
  // other reason is no answer either way — only a 404 or a 403 moves the latch
  // — so the error is swallowed and the latch still decides.
  try {
    await ref.watch(scheduledDryingsProvider.future);
  } on Object {
    // Deliberately ignored; see above.
  }
  return ref.watch(scheduledDryingRepositoryProvider).supportsScheduling();
});

/// The rows a given AMS unit's card should show: this printer's `pending` and
/// `failed` runs for that unit.
///
/// `running` is left out on purpose — while a run is live the AMS itself
/// reports the countdown, and a banner repeating it beside the flame chip would
/// say the same thing twice. `failed` is in because dispatch is the only place
/// a run can fail (a printer that was offline when it was scheduled turning out
/// to have firmware too old for it), and without the row the schedule would
/// simply disappear.
List<ScheduledDrying> scheduledDryingsFor(
  List<ScheduledDrying> all, {
  required int printerId,
  required int amsId,
}) =>
    [
      for (final row in all)
        if (row.printerId == printerId &&
            row.amsId == amsId &&
            (row.isPending || row.isFailed))
          row,
    ];

/// The drying temperatures and durations the server itself uses, from its
/// `drying_presets` setting — the same table the web's Queue Auto-Drying page
/// edits and the scheduler dries by.
///
/// Falls back to [defaultDryingPresets] whenever the setting is absent, empty
/// or unreadable, which covers the session that may not read settings at all:
/// `settings:read` rides on an API key's `can_read_status` scope, so a key
/// without it gets a 403 and `serverSettingsProvider` answers `{}`. The sheet
/// then offers what the server would have used anyway.
final dryingPresetsProvider = Provider<Map<String, DryPreset>>(
  (ref) => dryingPresetsFrom(
    ref.watch(serverSettingsProvider).valueOrNull?['drying_presets'],
  ),
);

/// Whether the server dries on its own, and how. Read-only — see [AutoDrying].
final autoDryingProvider = Provider<AutoDrying>(
  (ref) => autoDryingFrom(
    ref.watch(serverSettingsProvider).valueOrNull ?? const {},
  ),
);
