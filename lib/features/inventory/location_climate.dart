part of 'inventory_screen.dart';

/// Icon for a reading, by what the sensor measures. [LocationSensorCategory.other]
/// keeps a generic sensor glyph — a CO2 meter or a door contact is shown by its
/// own name, and guessing an icon for it would only mislead.
IconData _climateIcon(LocationSensorCategory category) => switch (category) {
  LocationSensorCategory.temperature => Icons.thermostat,
  LocationSensorCategory.humidity => Icons.water_drop_outlined,
  LocationSensorCategory.battery => Icons.battery_std_outlined,
  LocationSensorCategory.other => Icons.sensors,
};

/// What one reading says, as a pill's label: the number with its unit, the
/// on/off state of a binary sensor, or a dash when the entity has never been
/// readable.
String _climateValue(AppLocalizations l10n, LocationSensorReading reading) {
  if (reading.numeric) {
    return reading.formattedValue ?? l10n.inventoryClimateNoReading;
  }
  if (reading.state == null) return l10n.inventoryClimateNoReading;
  return reading.isOn ? l10n.commonOn : l10n.commonOff;
}

/// A storage location's sensor readings, one pill each.
///
/// Neutral unless something is wrong: an alerting reading is the only one that
/// takes the warm accent, so a shelf that is simply warm does not look like a
/// shelf that is too damp. An unreachable sensor keeps its last value and
/// trades its icon for a struck-through one — the value is still the most
/// useful thing on the pill, it just is not current.
class _ClimatePills extends StatelessWidget {
  const _ClimatePills({required this.readings});

  final List<LocationSensorReading> readings;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final reading in readings)
          Semantics(
            container: true,
            label: _semanticLabel(l10n, reading),
            child: ExcludeSemantics(
              child: DashPill(
                dense: true,
                label: '${reading.name} ${_climateValue(l10n, reading)}',
                accent: reading.alerting ? t.accentOrange : t.textSecondary,
                accentInk: reading.alerting
                    ? t.accentOrangeInk
                    : t.textSecondary,
                icon: reading.reachable
                    ? _climateIcon(reading.category)
                    : Icons.sensors_off,
              ),
            ),
          ),
      ],
    );
  }

  /// The pill spelled out: a screen reader gets neither the icon nor the
  /// colour, which are the whole of how "too damp" and "not current" are shown.
  static String _semanticLabel(
    AppLocalizations l10n,
    LocationSensorReading reading,
  ) {
    final value = _climateValue(l10n, reading);
    if (!reading.reachable) {
      return l10n.inventoryClimateReadingStale(reading.name, value);
    }
    if (reading.alerting) {
      return l10n.inventoryClimateReadingAlerting(reading.name, value);
    }
    return l10n.inventoryClimateReading(reading.name, value);
  }
}

/// Every storage location that has a sensor bound to it, with what those
/// sensors read.
///
/// Read-only, and the note says why: binding an entity needs the Home
/// Assistant URL and token that live in the server's own settings, and the
/// permission for it is one no API key can hold.
void _openLocationClimate(BuildContext context) {
  dashSurfaceSheet<void>(
    context,
    builder: (_) => const _LocationClimateSheet(),
  );
}

class _LocationClimateSheet extends ConsumerWidget {
  const _LocationClimateSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final climates = ref.watch(locationClimateProvider).valueOrNull ?? const {};
    final entries = climates.values.toList();

    return logTag(
      'sheet.location_climate',
      DraggableSheetSurface(
        initialSize: 0.5,
        minSize: 0.3,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text(l10n.inventoryClimateTitle, style: theme.textTheme.titleLarge),
            InlineNote(
              l10n.inventoryClimateSource,
              icon: Icons.info_outline,
              padding: const EdgeInsets.only(top: 8, bottom: 4),
            ),
            for (final climate in entries)
              Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: t.subCard,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: climate.alerting
                        ? t.accentOrange.withValues(alpha: 0.5)
                        : t.subCardBorder,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(climate.location.name, style: t.titleSm),
                        ),
                        Text(
                          l10n.inventorySpoolCount(climate.location.spoolCount),
                          style: t.label.copyWith(color: t.textSecondary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _ClimatePills(readings: climate.readings),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
