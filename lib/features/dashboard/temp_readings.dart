import 'package:flutter/painting.dart';

import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';

enum TempKind { nozzle, bed, chamber, unknown }

enum HeatState { off, heating, atTarget, cooling }

/// Pair of readings (current + target) for one sensor. Label is translated
/// at render time (with [BuildContext]).
class TempReading {
  const TempReading({
    required this.kind,
    required this.raw,
    required this.actual,
    required this.target,
    this.index,
    this.airductIsHeating,
  });

  final TempKind kind;
  final String raw; // raw key—shown for unknown sensor
  final int? index; // nozzle number (e.g., 2) or null
  final double? actual;
  final double? target;

  /// Chamber air duct mode (heating/cooling); set ONLY for chamber tile where we
  /// show it instead of the setpoint. null = unknown/n.a.
  final bool? airductIsHeating;

  /// Diagnostic identifier of this tile. [raw] is the server's own key
  /// (`nozzle`, `nozzle_2`, `bed`), which keeps the log's vocabulary the same on
  /// both sides — but it is the server's string, so anything not shaped like an
  /// identifier falls back to the bare tile name rather than going in verbatim.
  String get logId => _logId('printer.temperature');

  String _logId(String base) =>
      RegExp(r'^\w+$').hasMatch(raw) ? '${base}_$raw' : base;

  String label(AppLocalizations l10n) => switch (kind) {
    TempKind.nozzle =>
      index == null ? l10n.tempNozzle : l10n.tempNozzleNumbered('$index'),
    TempKind.bed => l10n.tempBed,
    TempKind.chamber => l10n.tempChamber,
    TempKind.unknown => raw,
  };

  /// Upper bound of the gauge sweep per sensor (approx working range).
  ///
  /// [chamberMax] is the server's own chamber ceiling, read from
  /// [chamberMaxTargetProvider] by whoever renders — 60 before server 1.2.6 and
  /// 65 from it. Passed in on every call rather than stored on the reading
  /// because this object is built by [PrinterCard], a plain `StatefulWidget`
  /// with no `ref`, while both consumers of these three are Consumers already.
  /// The chamber tracks it so a target at the ceiling cannot peg the needle
  /// past the end of the sweep.
  double gaugeMax(int chamberMax) => switch (kind) {
    TempKind.nozzle => 300,
    TempKind.bed => 120,
    TempKind.chamber => chamberMax.toDouble(),
    TempKind.unknown => 300,
  };

  /// Gauge/value color by thermal state (same for every sensor): heating or
  /// holding at the setpoint → orange; already above the setpoint (cooling) or
  /// no setpoint → blue. A small tolerance avoids color flicker around target.
  /// [target] overrides the reading's own setpoint (for optimistic overlay).
  Color gaugeColor(DashTokens t, {double? target}) =>
      switch (heatState(target: target)) {
        HeatState.off || HeatState.cooling => t.accentBlue,
        HeatState.heating || HeatState.atTarget => t.accentOrange,
      };

  /// [gaugeColor] for text. The orange fill reads 2.77:1 on the light ground, under
  /// the 3:1 that even a 44 px number needs, so text takes the orange ink.
  Color gaugeInk(DashTokens t, {double? target}) =>
      switch (heatState(target: target)) {
        HeatState.off || HeatState.cooling => t.accentBlueInk,
        HeatState.heating || HeatState.atTarget => t.accentOrangeInk,
      };

  /// Where the reading stands against its setpoint, within the same tolerance
  /// as [gaugeColor]. No reading yet with a setpoint counts as heating.
  HeatState heatState({double? target}) {
    final tgt = target ?? this.target;
    const tolerance = 2.0;
    final now = actual;
    if (tgt == null || tgt <= 0) return HeatState.off;
    if (now == null || now < tgt - tolerance) return HeatState.heating;
    if (now > tgt + tolerance) return HeatState.cooling;
    return HeatState.atTarget;
  }

  /// Upper bound the target slider allows. Slightly under the server's hard
  /// caps (nozzle 320 / bed 140) to a sane working range; chamber = server max.
  int maxTarget(int chamberMax) => switch (kind) {
    TempKind.nozzle => 300,
    TempKind.bed => 120,
    TempKind.chamber => chamberMax,
    TempKind.unknown => 300,
  };

  /// Slider/stepper granularity: 1° everywhere for smooth fine control.
  int get targetStep => 1;

  /// Common quick-pick targets shown as chips in the sheet (Off has its own
  /// button, so it's not listed here).
  ///
  /// The chamber keeps its familiar four and gains the ceiling as a fifth when
  /// the server allows more than 60 — rather than moving the last chip up,
  /// which would take away the 60 people actually use. The [Wrap] takes the
  /// extra chip onto a second row if it has to.
  List<int> presets(int chamberMax) => switch (kind) {
    TempKind.nozzle => const [200, 220, 240, 260],
    TempKind.bed => const [50, 60, 80, 100],
    TempKind.chamber => [30, 40, 50, 60, if (chamberMax > 60) chamberMax],
    TempKind.unknown => const [],
  };
}

/// Group raw temperature keys into current/target pairs and order known sensors
/// (nozzle, bed, chamber) before unknown ones.
List<TempReading> buildTempReadings(
  Map<String, double>? temps,
  bool? airductIsHeating,
) {
  if (temps == null || temps.isEmpty) return const [];

  final actuals = <String, double>{};
  final targets = <String, double>{};
  for (final entry in temps.entries) {
    var base = entry.key;
    final isTarget = base.endsWith('_target');
    if (isTarget) base = base.substring(0, base.length - '_target'.length);
    if (base.endsWith('_temper')) {
      base = base.substring(0, base.length - '_temper'.length);
    }
    (isTarget ? targets : actuals)[base] = entry.value;
  }

  const orderHint = ['nozzle', 'bed', 'chamber'];
  int rank(String base) {
    final stem = RegExp(r'^([a-z]+)').firstMatch(base)?.group(1) ?? base;
    final i = orderHint.indexOf(stem);
    return i == -1 ? orderHint.length : i;
  }

  final bases = {...actuals.keys, ...targets.keys}.toList()
    ..sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : a.compareTo(b);
    });

  return [
    for (final base in bases)
      _readingFor(base, actuals[base], targets[base], airductIsHeating),
  ];
}

TempReading _readingFor(
  String base,
  double? actual,
  double? target,
  bool? airductIsHeating,
) {
  final numbered = RegExp(r'^([a-z]+)_(\d+)$').firstMatch(base);
  final stem = numbered?.group(1) ?? base;
  final index = numbered == null ? null : int.tryParse(numbered.group(2)!);

  final kind = switch (stem) {
    'nozzle' => TempKind.nozzle,
    'bed' => TempKind.bed,
    'chamber' => TempKind.chamber,
    _ => TempKind.unknown,
  };

  return TempReading(
    kind: kind,
    raw: base,
    index: kind == TempKind.nozzle ? index : null,
    actual: actual,
    target: target,
    // Air duct applies to chamber only.
    airductIsHeating: kind == TempKind.chamber ? airductIsHeating : null,
  );
}
