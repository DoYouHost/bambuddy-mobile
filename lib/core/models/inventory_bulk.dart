/// Models for the bulk spool routes (`/spools/bulk-*`), shared by both
/// inventory backends. The routes exist from server 0.2.5b1; the app falls back
/// to per-spool calls on older ones, so nothing here may be required for the
/// single-spool path to work.
library;

import 'json_utils.dart';

/// A partial spool edit applied to a whole selection.
///
/// Sparse by construction: `null` means "leave this field as it is", and the
/// serializers drop it. There is deliberately no way to *clear* a field in
/// bulk — a blank input means "unchanged", not "erase on every spool", the
/// same decision the web client took (issue #1795). Clearing stays in the
/// per-spool editor, where it is one spool at a time.
///
/// `SpoolDraft` cannot serve here: its `material` is non-nullable and always
/// serialized, so it has no way to express "change only the brand".
///
/// [rgba] is expected already normalized to `RRGGBBAA` (`normalizeRgba` in the
/// inventory UI) — the server pattern is `^[0-9A-Fa-f]{8}$` and rejects the
/// whole batch otherwise.
class SpoolBulkPatch {
  const SpoolBulkPatch({
    this.material,
    this.subtype,
    this.brand,
    this.colorName,
    this.rgba,
    this.storageLocation,
    this.slicerFilament,
    this.slicerFilamentName,
    this.costPerKg,
    this.note,
    this.labelWeight,
    this.coreWeight,
    this.category,
    this.lowStockThresholdPct,
  });

  final String? material;
  final String? subtype;
  final String? brand;
  final String? colorName;
  final String? rgba;
  final String? storageLocation;
  final String? slicerFilament;
  final String? slicerFilamentName;
  final double? costPerKg;
  final String? note;
  final int? labelWeight;
  final int? coreWeight;
  final String? category;
  final int? lowStockThresholdPct;

  /// `weight_used` is absent on purpose: the native route sets
  /// `weight_locked = true` by itself whenever the patch carries it
  /// (`routes/inventory.py::bulk_update_spools`), which would freeze AMS
  /// auto-sync on every selected spool as a side effect of a mass edit.
  ///
  /// A free-text [storageLocation] is safe to send — the server creates the
  /// catalog entry when the name is new
  /// (`services/location_service.py::resolve_location_by_name` defaults to
  /// `create: True`). `location_id` is what would be dangerous: an id the
  /// server does not know fails the *whole* batch with 400.
  Map<String, dynamic> toNativeJson() => {
        if (material != null) 'material': material,
        if (subtype != null) 'subtype': subtype,
        if (brand != null) 'brand': brand,
        if (colorName != null) 'color_name': colorName,
        if (rgba != null) 'rgba': rgba,
        if (storageLocation != null) 'storage_location': storageLocation,
        if (slicerFilament != null) 'slicer_filament': slicerFilament,
        if (slicerFilamentName != null)
          'slicer_filament_name': slicerFilamentName,
        if (costPerKg != null) 'cost_per_kg': costPerKg,
        if (note != null) 'note': note,
        if (labelWeight != null) 'label_weight': labelWeight,
        if (coreWeight != null) 'core_weight': coreWeight,
        if (category != null) 'category': category,
        if (lowStockThresholdPct != null)
          'low_stock_threshold_pct': lowStockThresholdPct,
      };

  /// The narrower set Spoolman's schema accepts. `category` and
  /// `low_stock_threshold_pct` are native-only columns and are dropped, the
  /// same way `SpoolDraft.toSpoolmanJson` drops them on the per-spool path.
  /// `core_weight` is kept for that parity even though Spoolman stores it on
  /// the filament type rather than the spool and silently ignores it here.
  Map<String, dynamic> toSpoolmanJson() => {
        if (material != null) 'material': material,
        if (subtype != null) 'subtype': subtype,
        if (brand != null) 'brand': brand,
        if (colorName != null) 'color_name': colorName,
        if (rgba != null) 'rgba': rgba,
        if (storageLocation != null) 'storage_location': storageLocation,
        if (slicerFilament != null) 'slicer_filament': slicerFilament,
        if (slicerFilamentName != null)
          'slicer_filament_name': slicerFilamentName,
        if (costPerKg != null) 'cost_per_kg': costPerKg,
        if (note != null) 'note': note,
        if (labelWeight != null) 'label_weight': labelWeight,
        if (coreWeight != null) 'core_weight': coreWeight,
      };

  /// Nothing to send — the routes answer 400 to an empty `update`, and the
  /// Apply button stays disabled while this holds.
  bool get isEmpty => toNativeJson().isEmpty;

  /// How many fields the edit touches, for the confirmation copy.
  int get fieldCount => toNativeJson().length;
}

/// What a bulk call did, normalized across the two backends' answers.
///
/// Native reports unknown and already-in-state ids as lists (`not_found`,
/// `already_archived`, `already_active`); Spoolman loops per-spool proxy calls
/// and reports `errors: [{id, status, detail}]`. Both reduce to the same four
/// numbers.
class BulkOutcome {
  const BulkOutcome({
    this.ok = 0,
    this.skipped = 0,
    this.failed = 0,
    this.notFound = const [],
  });

  /// Reads `{ok: n, …}` for the four `{ids: […]}` routes.
  ///
  /// [okKey] is the route's own name for the count (`updated`, `deleted`,
  /// `archived`, `restored`); [skippedKey] names the native list of ids that
  /// were already in the requested state, and is absent on the routes that
  /// have none.
  factory BulkOutcome.fromJson(
    Map<String, dynamic>? json, {
    required String okKey,
    String? skippedKey,
  }) {
    final data = json ?? const <String, dynamic>{};
    final notFound = _idList(data['not_found']);
    final errors = data['errors'];
    final errorCount = errors is List ? errors.length : 0;
    return BulkOutcome(
      ok: toIntOrNull(data[okKey]) ?? 0,
      skipped: skippedKey == null ? 0 : _countOf(data[skippedKey]),
      failed: notFound.length + errorCount,
      notFound: notFound,
    );
  }

  /// Reads `{reset: n}`, the one shape that reports neither failures nor
  /// unknown ids. Native counts the rows it found, Spoolman the calls that
  /// succeeded — either way the gap against [requested] is what did not
  /// happen, and saying "2 failed" is the only honest reading of it.
  factory BulkOutcome.fromResetJson(Map<String, dynamic>? json, int requested) {
    final ok = toIntOrNull((json ?? const {})['reset']) ?? 0;
    return BulkOutcome(ok: ok, failed: requested > ok ? requested - ok : 0);
  }

  static const empty = BulkOutcome();

  /// Rows the server actually changed.
  final int ok;

  /// Rows already in the requested state. Counted apart from [ok] because
  /// "3 archived, 2 already archived" is worth telling the user, and apart
  /// from [failed] because neither is a failure — the end state is the one
  /// that was asked for.
  final int skipped;

  /// Per-spool errors plus ids the server does not know.
  final int failed;

  final List<int> notFound;

  bool get isComplete => failed == 0;

  /// Sums the chunks a selection was split into for the 500-id cap.
  BulkOutcome operator +(BulkOutcome other) => BulkOutcome(
        ok: ok + other.ok,
        skipped: skipped + other.skipped,
        failed: failed + other.failed,
        notFound: [...notFound, ...other.notFound],
      );
}

/// Ints out of a server-sent id list, tolerant of the string-typed numbers an
/// older build or a proxy may hand back.
List<int> _idList(Object? value) {
  if (value is! List) return const [];
  return [
    for (final item in value) ?toIntOrNull(item),
  ];
}

/// Length of a list, or the number itself — `already_archived` is a list of ids
/// on native, and a plain count is the shape a future build could switch to
/// without it being an error.
int _countOf(Object? value) =>
    value is List ? value.length : toIntOrNull(value) ?? 0;

/// How many ids one bulk request may carry. The server's own cap
/// (`Field(..., min_length=1, max_length=500)` on the request schemas) — a
/// larger selection is split rather than refused, so "select all" stays usable
/// on a shelf of any size.
const bulkIdLimit = 500;

/// Splits [ids] into requests that fit [bulkIdLimit].
///
/// An empty selection yields no chunks at all, which is what the routes need:
/// they reject an empty `ids` list, so the right number of requests to send for
/// nothing is zero.
List<List<int>> chunkIds(List<int> ids, {int limit = bulkIdLimit}) => [
      for (var start = 0; start < ids.length; start += limit)
        ids.sublist(start, start + limit > ids.length ? ids.length : start + limit),
    ];
