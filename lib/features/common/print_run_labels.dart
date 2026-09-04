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
