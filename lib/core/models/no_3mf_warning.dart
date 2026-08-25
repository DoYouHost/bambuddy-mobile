import 'json_utils.dart';

/// Why a print archived without its 3MF — the slug from
/// `GET /archives/no-3mf-warning`.
///
/// The advice differs per case and the original single wording was wrong for
/// two of the three (#2780): it sent H2-series and P2S owners to switch on a
/// setting that was already on, and blamed the slicer when the real answer was
/// an empty card slot. The slugs are contract (`print_storage.py`), so an
/// unrecognized one — a cause the server learns to tell apart after this app
/// shipped — degrades to [slicerSetting], the wording that was shown
/// unconditionally before any reason existed.
enum No3mfReason {
  /// The printer kept the sliced file on internal storage, which FTPS does not
  /// serve at all. Nothing for the user to switch on.
  internalStorage,

  /// No card or stick in the printer, so the file had nowhere to land.
  noExternalStorage,

  /// No reason recorded: the original case, "Store sent files on external
  /// storage" off in the slicer. Also what an older server's answer maps to,
  /// since it does not send the field.
  slicerSetting;

  static No3mfReason fromSlug(dynamic value) => switch (toStringOrNull(value)) {
        'internal_storage' => No3mfReason.internalStorage,
        'no_external_storage' => No3mfReason.noExternalStorage,
        _ => No3mfReason.slicerSetting,
      };
}

/// Whether to nudge the user about prints that archived without their 3MF.
///
/// True iff any archive in the last 30 days came through the no-3MF fallback.
/// The server keeps no dismissal state — that is the client's to remember.
class No3mfWarning {
  const No3mfWarning({
    required this.hasFallback,
    required this.reason,
  });

  factory No3mfWarning.fromJson(Map<String, dynamic> json) => No3mfWarning(
        hasFallback: json['has_fallback'] == true,
        reason: No3mfReason.fromSlug(json['reason']),
      );

  static const none =
      No3mfWarning(hasFallback: false, reason: No3mfReason.slicerSetting);

  final bool hasFallback;

  /// Meaningless while [hasFallback] is false — the server sends
  /// `{has_fallback: false, reason: null}` and the banner is not shown at all.
  final No3mfReason reason;
}
