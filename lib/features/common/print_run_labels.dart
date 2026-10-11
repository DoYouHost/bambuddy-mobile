import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter/material.dart';

import '../../core/models/print_run.dart';
import '../../l10n/app_localizations.dart';

/// The label for a run's failure cause.
///
/// The server stores and groups by an i18n **key** (`filamentRunout`) and
/// leaves the translating to whoever renders it — so this is what stands
/// between the reader and a screen that says "filamentRunout".
///
/// Three inputs it has to survive, all of which turn up in practice:
///
/// - null or empty — the run was never classified.
/// - the literal `Unknown`, which is what `GET /archives/analysis/failures`
///   names that bucket. It arrives as data, not as a key.
/// - anything else — shown exactly as it came. Older web builds saved the
///   *translated label* instead of the key, and the archive-side PATCH that
///   mirrors this field validates nothing, so free text is a real value.
String failureReasonLabel(AppLocalizations l10n, String? reason) {
  final key = reason?.trim() ?? '';
  return switch (key) {
    '' || 'Unknown' => l10n.failureReasonUnknown,
    'adhesionFailure' => l10n.failureReasonAdhesion,
    'spaghettiDetached' => l10n.failureReasonSpaghetti,
    'layerShift' => l10n.failureReasonLayerShift,
    'cloggedNozzle' => l10n.failureReasonCloggedNozzle,
    'filamentRunout' => l10n.failureReasonFilamentRunout,
    'warping' => l10n.failureReasonWarping,
    'stringing' => l10n.failureReasonStringing,
    'underExtrusion' => l10n.failureReasonUnderExtrusion,
    'powerFailure' => l10n.failureReasonPowerFailure,
    'userCancelled' => l10n.failureReasonUserCancelled,
    'other' => l10n.failureReasonOther,
    _ => key,
  };
}

/// The label for a run's status.
///
/// `aborted` is here although the print log's own editor cannot write it: rows
/// carry it from the archive side, and a row the app can show is a row the app
/// has to name. An unrecognised status is shown as it came rather than hidden.
String printRunStatusLabel(AppLocalizations l10n, String status) =>
    switch (status.trim()) {
      'completed' => l10n.printLogStatusCompleted,
      'failed' => l10n.printLogStatusFailed,
      'stopped' => l10n.printLogStatusStopped,
      'cancelled' => l10n.printLogStatusCancelled,
      'skipped' => l10n.printLogStatusSkipped,
      'aborted' => l10n.printLogStatusAborted,
      _ => status,
    };

/// The entries of a failure-cause picker: [none] (value `''`), the vocabulary
/// the server validates, and the cause a row already [carries] when it is
/// outside that list — an older web build saved translated labels, and
/// without its own entry the field would read as empty.
///
/// [ids] are the log identifiers of the three kinds of row, taken whole from
/// the call site: an interpolated one is invisible to
/// `action_tag_vocabulary_test.dart`, which reads them out of the source.
List<DropdownMenuEntry<String>> failureReasonEntries(
  AppLocalizations l10n, {
  required String none,
  required String? carries,
  required ({String none, String option, String legacy}) ids,
}) => [
  DropdownMenuEntry(
    value: '',
    label: none,
    labelWidget: logTag(ids.none, Text(none)),
  ),
  for (final key in printLogFailureReasons)
    DropdownMenuEntry(
      value: key,
      label: failureReasonLabel(l10n, key),
      labelWidget: logTag(ids.option, Text(failureReasonLabel(l10n, key))),
    ),
  if (carries != null && !printLogFailureReasons.contains(carries))
    DropdownMenuEntry(
      value: carries,
      label: failureReasonLabel(l10n, carries),
      labelWidget: logTag(ids.legacy, Text(failureReasonLabel(l10n, carries))),
    ),
];
