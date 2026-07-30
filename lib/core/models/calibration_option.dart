/// Tri-state print calibration option — `bed_levelling`, `flow_cali` and
/// `nozzle_offset_cali` on a queue item.
///
/// bambuddy 1.2.5 turned these three from plain booleans into
/// `Literal["off", "on", "auto"]` (`backend/app/schemas/print_queue.py`), where
/// `auto` is BambuStudio's "let the printer decide — skip if it was done
/// recently". The change shipped without a CHANGELOG entry, and the generated
/// `as bool?` cast it broke threw on every queue record, so a correct 200 left
/// the queue screen empty (`docs/plans/07-queue-cali-enum.md`).
///
/// Older servers keep sending and expecting booleans, so both wire forms have to
/// work in both directions — see [calibrationFromJson] and [toWire].
enum CalibrationOption {
  off,
  on,
  auto;

  /// Value for a request body, or `null` to leave the key out of the body.
  ///
  /// [on] and [off] always go as booleans: pre-1.2.5 servers take only that
  /// form, and 1.2.5+ maps it back through its own `_coerce_tristate` validator
  /// (`bool → "on"/"off"`), so a boolean is the one spelling every server
  /// understands. Only [auto] needs the string form, and only a [triState]
  /// server has somewhere to put it — elsewhere the key is omitted, which leaves
  /// a stored value untouched on an update and lets the server apply its own
  /// default on a create. Both are honest about "this server cannot store auto";
  /// sending a boolean instead would quietly turn the user's `auto` into
  /// on-or-off.
  Object? toWire({required bool triState}) => switch (this) {
        CalibrationOption.on => true,
        CalibrationOption.off => false,
        CalibrationOption.auto => triState ? 'auto' : null,
      };

  /// How the option reads on a control that has no `auto` position (an older
  /// server). `auto` leans on: on every affected field it means the printer may
  /// still run the calibration, just not unconditionally.
  bool get asSwitch => this != CalibrationOption.off;
}

/// Tolerant parse of whatever either server generation sends, falling back to
/// [CalibrationOption.auto].
///
/// The fallback only fires on a missing or unrecognised value — both server
/// versions always send these fields — and `auto` is what every 1.2.5 schema
/// carrying them defaults to.
CalibrationOption calibrationFromJson(dynamic value) =>
    calibrationOrNull(value) ?? CalibrationOption.auto;

/// [calibrationFromJson] without the fallback: `null` when [value] is missing or
/// is nothing this contract has ever used.
///
/// Accepts more than the two server versions emit on purpose — the int form is
/// what 1.2.5's own `_coerce_tristate` accepts (`getValueInt` parity: `off=0`,
/// `on=1`, `auto=2`), and the `"true"`/`"false"` strings are what it maps for
/// un-migrated database rows. Reading a shape the server is willing to write
/// costs nothing here and is one less way to empty a screen.
CalibrationOption? calibrationOrNull(dynamic value) => switch (value) {
      bool b => b ? CalibrationOption.on : CalibrationOption.off,
      int i => switch (i) {
          0 => CalibrationOption.off,
          1 => CalibrationOption.on,
          2 => CalibrationOption.auto,
          _ => null,
        },
      String s => switch (s.trim().toLowerCase()) {
          'on' || 'true' || '1' => CalibrationOption.on,
          'off' || 'false' || '0' => CalibrationOption.off,
          'auto' || '2' => CalibrationOption.auto,
          _ => null,
        },
      _ => null,
    };
