part of 'printer_card.dart';

/// Temperature gauge tile (design "gauge card"): a circular gauge in the
/// top-right, sensor label, and the current value in large mono type. Chamber
/// additionally shows the air-duct heating/cooling badge; other sensors show
/// their setpoint (→ target) when actively heating.
class _GaugeTile extends StatelessWidget {
  const _GaugeTile({required this.reading});

  final _TempReading reading;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final actual = reading.actual;
    final target = reading.target;
    final accent = reading.gaugeColor(t);
    final hasTarget = target != null && target > 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: t.subCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.subCardBorder),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 0,
            right: 0,
            // Target lives inside the ring ("-" when unset) → no extra row below.
            child: TempGauge(
              fraction: actual == null ? 0 : actual / reading.gaugeMax,
              color: accent,
              trackColor: t.gaugeTrack,
              centerText: hasTarget ? '${target.toStringAsFixed(0)}°' : '-',
              centerColor: hasTarget ? accent : t.textTertiary,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Reserve the gauge's corner: pad the label so it never collides.
              Padding(
                padding: const EdgeInsets.only(right: 40),
                child: Text(
                  reading.label(l10n).toUpperCase(),
                  style: TextStyle(
                    fontFamily: DashTokens.fontUi,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                    color: t.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    actual == null ? '—' : '${actual.toStringAsFixed(0)}°',
                    style: TextStyle(
                      fontFamily: DashTokens.fontMono,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      height: 1.0,
                      color: t.textPrimary,
                    ),
                  ),
                  // Chamber cooling/heating sits inline, in the free space below
                  // the ring — keeps every tile the same compact height.
                  if (reading.airductIsHeating != null) ...[
                    const Spacer(),
                    _AirductBadge(heating: reading.airductIsHeating!),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Chamber air-duct indicator: snowflake+"Cooling" (blue) or flame+"Heating"
/// (orange). Shown inside the chamber gauge tile.
class _AirductBadge extends StatelessWidget {
  const _AirductBadge({required this.heating});

  final bool heating;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final color = heating ? t.accentOrange : t.accentBlue;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(heating ? Icons.local_fire_department : Icons.ac_unit,
              size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            heating ? l10n.ctrlAirductHeating : l10n.ctrlAirductCooling,
            style: TextStyle(
              fontFamily: DashTokens.fontUi,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Status pill in the card header ("IDLE", "RUNNING", "OFFLINE"). Connected →
/// green; offline → red tinted with a vivid border.
class _StateChip extends StatelessWidget {
  const _StateChip({
    required this.label,
    required this.connected,
    this.active = false,
    this.offline = false,
  });

  final String label;
  final bool connected;
  final bool active;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final scheme = Theme.of(context).colorScheme;
    final Color bg;
    final Color fg;
    final BoxBorder? border;
    if (offline) {
      bg = scheme.error.withValues(alpha: 0.14);
      fg = scheme.error;
      border = Border.all(color: scheme.error, width: 1.5);
    } else {
      bg = t.accentGreen.withValues(alpha: 0.16);
      fg = t.accentGreenInk;
      border = null;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: border,
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontFamily: DashTokens.fontUi,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: fg,
        ),
      ),
    );
  }
}

enum _TempKind { nozzle, bed, chamber, unknown }

/// Pair of readings (current + target) for one sensor. Label is translated
/// at render time (with [BuildContext]).
class _TempReading {
  const _TempReading({
    required this.kind,
    required this.raw,
    required this.actual,
    required this.target,
    this.index,
    this.airductIsHeating,
  });

  final _TempKind kind;
  final String raw; // raw key—shown for unknown sensor
  final int? index; // nozzle number (e.g., 2) or null
  final double? actual;
  final double? target;

  /// Chamber air duct mode (heating/cooling); set ONLY for chamber tile where we
  /// show it instead of the setpoint. null = unknown/n.a.
  final bool? airductIsHeating;

  String label(AppLocalizations l10n) => switch (kind) {
        _TempKind.nozzle =>
          index == null ? l10n.tempNozzle : l10n.tempNozzleNumbered('$index'),
        _TempKind.bed => l10n.tempBed,
        _TempKind.chamber => l10n.tempChamber,
        _TempKind.unknown => raw,
      };

  /// Upper bound of the gauge sweep per sensor (approx working range).
  double get gaugeMax => switch (kind) {
        _TempKind.nozzle => 300,
        _TempKind.bed => 120,
        _TempKind.chamber => 60,
        _TempKind.unknown => 300,
      };

  /// Gauge fill color per sensor: nozzle→orange, bed→green, chamber→blue.
  Color gaugeColor(DashTokens t) => switch (kind) {
        _TempKind.nozzle => t.accentOrange,
        _TempKind.bed => t.accentGreen,
        _TempKind.chamber => t.accentBlue,
        _TempKind.unknown => t.accentGreen,
      };
}

/// Group raw temperature keys into current/target pairs and order known sensors
/// (nozzle, bed, chamber) before unknown ones.
List<_TempReading> _buildReadings(
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

_TempReading _readingFor(
  String base,
  double? actual,
  double? target,
  bool? airductIsHeating,
) {
  final numbered = RegExp(r'^([a-z]+)_(\d+)$').firstMatch(base);
  final stem = numbered?.group(1) ?? base;
  final index = numbered == null ? null : int.tryParse(numbered.group(2)!);

  final kind = switch (stem) {
    'nozzle' => _TempKind.nozzle,
    'bed' => _TempKind.bed,
    'chamber' => _TempKind.chamber,
    _ => _TempKind.unknown,
  };

  return _TempReading(
    kind: kind,
    raw: base,
    index: kind == _TempKind.nozzle ? index : null,
    actual: actual,
    target: target,
    // Air duct applies to chamber only.
    airductIsHeating: kind == _TempKind.chamber ? airductIsHeating : null,
  );
}

String _durationText(AppLocalizations l10n, int minutes) => minutes < 60
    ? l10n.durationMinutes(minutes)
    : l10n.durationHoursMinutes(minutes ~/ 60, minutes % 60);

/// ETA as HH:mm = now + remaining minutes.
String _etaTime(int remainingMinutes) {
  final eta = DateTime.now().add(Duration(minutes: remainingMinutes));
  final hh = eta.hour.toString().padLeft(2, '0');
  final mm = eta.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}
