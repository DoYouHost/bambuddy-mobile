import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/models/print_run.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';

/// The label for a run's failure cause. The server stores and groups by an i18n **key**
/// (`filamentRunout`) and leaves the translating to the renderer. Three inputs it has
/// to survive: null or empty (never classified); the literal `Unknown`, which
/// `GET /archives/analysis/failures` names that bucket and which arrives as data, not
/// a key; and anything else, shown exactly as it came, since older web builds saved
/// the translated label and the archive PATCH validates nothing.
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

/// The colour a run's status is shown in, as a fill and as ink: a failure in
/// the danger colour, a success in the accent, anything else quiet.
(Color, Color) printRunTone(DashTokens t, String status) =>
    printRunIsFailure(status)
    ? (t.danger, t.dangerInk)
    : printRunIsSuccess(status)
    ? (t.accentGreen, t.accentGreenInk)
    : (t.textTertiary, t.textTertiary);

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
