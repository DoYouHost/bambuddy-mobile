part of 'printer_card.dart';

class _TempTile extends StatelessWidget {
  const _TempTile({required this.reading});

  final _TempReading reading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final actual = reading.actual;
    final target = reading.target;

    final iconColor = _tempIconColor(scheme, actual, target);
    // Show target only if set (>0); 0 = heating off.
    final hasTarget = target != null && target > 0;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Icon top-left + sensor label; for chamber, air duct indicator (heating/
          // cooling) on right instead of separate chip.
          Row(
            children: [
              Icon(reading.icon, size: 16, color: iconColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  reading.label(l10n),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (reading.airductIsHeating != null)
                _AirductBadge(heating: reading.airductIsHeating!),
            ],
          ),
          const SizedBox(height: 8),
          // Current: large, vivid color, left-aligned. Target: smaller, semi-
          // transparent, right-aligned.
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                actual == null ? '—' : '${actual.toStringAsFixed(0)}°',
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: iconColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (hasTarget) ...[
                const Spacer(),
                Text(
                  '${target.toStringAsFixed(0)}°',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: iconColor.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Chamber air duct indicator pinned to chamber temp tile: icon +
/// "Heating"/"Cooling". Replaces former separate chip to keep chamber info unified.
class _AirductBadge extends StatelessWidget {
  const _AirductBadge({required this.heating});

  final bool heating;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final color = heating ? const Color(0xFFFF8A50) : const Color(0xFF4FC3F7);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          heating ? Icons.local_fire_department : Icons.ac_unit,
          size: 13,
          color: color,
        ),
        const SizedBox(width: 3),
        Text(
          heating ? l10n.ctrlAirductHeating : l10n.ctrlAirductCooling,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
        ),
      ],
    );
  }
}

/// Icon color for temperature tile depends on sensor state: white when target
/// unset, blue when cooling (actual above target), orange when heating/holding high temp.
Color _tempIconColor(ColorScheme scheme, double? actual, double? target) {
  // Target unset (null or 0 = heating off)→neutral white.
  if (target == null || target <= 0) return scheme.onSurface;
  // Tolerance: minor fluctuations at target shouldn't flicker the color.
  const tolerance = 2.0;
  if (actual != null && actual > target + tolerance) {
    return const Color(0xFF4FC3F7); // cooling—blue
  }
  return const Color(0xFFFF8A50); // heating/high temp—orange
}

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

  /// OFFLINE variant: light red background + vivid red border so disconnected
  /// printer stands out even in collapsed card.
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Chip(
      visualDensity: VisualDensity.compact,
      backgroundColor: offline
          ? scheme.error.withValues(alpha: 0.12)
          : (active
                ? scheme.primaryContainer
                : (connected
                      ? scheme.secondaryContainer
                      : scheme.surfaceContainerHighest)),
      side: offline
          ? BorderSide(color: scheme.error, width: 1.5)
          : BorderSide.none,
      label: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          color: offline ? scheme.error : null,
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
  /// show it instead of separate chip. null = unknown/n.a.
  final bool? airductIsHeating;

  String label(AppLocalizations l10n) => switch (kind) {
    _TempKind.nozzle =>
      index == null ? l10n.tempNozzle : l10n.tempNozzleNumbered('$index'),
    _TempKind.bed => l10n.tempBed,
    _TempKind.chamber => l10n.tempChamber,
    _TempKind.unknown => raw,
  };

  IconData get icon => switch (kind) {
    _TempKind.nozzle => Icons.local_fire_department,
    _TempKind.bed => Icons.wb_iridescent,
    _TempKind.chamber => Icons.thermostat,
    _TempKind.unknown => Icons.device_thermostat,
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
