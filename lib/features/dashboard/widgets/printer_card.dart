import 'package:flutter/material.dart';

import '../../../core/models/printer_status.dart';
import '../../../data/printers_repository.dart';
import '../../../l10n/app_localizations.dart';

class PrinterCard extends StatelessWidget {
  const PrinterCard({super.key, required this.item});

  final PrinterWithStatus item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final status = item.status;
    final connected = status?.connected ?? false;
    final printing = status?.isPrinting ?? false;
    final readings = _buildReadings(status?.temperatures);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.print,
                  color: connected
                      ? theme.colorScheme.primary
                      : theme.disabledColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.printer.name,
                    style: theme.textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _StateChip(
                  label: status == null
                      ? l10n.statusUnavailable
                      : (status.state ??
                          (connected ? l10n.online : l10n.offline)),
                  connected: connected,
                  active: printing,
                ),
              ],
            ),
            if (printing) ...[
              const SizedBox(height: 10),
              _PrintPanel(status: status!),
            ],
            if (readings.isNotEmpty) ...[
              const SizedBox(height: 10),
              _TempGrid(readings: readings),
            ],
          ],
        ),
      ),
    );
  }
}

/// Panel aktywnego wydruku: nazwa, pasek postępu z %, ETA i warstwy.
class _PrintPanel extends StatelessWidget {
  const _PrintPanel({required this.status});

  final PrinterStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final progress = status.progress;
    final name = status.currentPrint ?? status.gcodeFile;

    final meta = <Widget>[
      if (status.remainingTime != null)
        _MetaItem(
          icon: Icons.schedule,
          text: l10n.remaining(_durationText(l10n, status.remainingTime!)),
        ),
      if (status.remainingTime != null)
        _MetaItem(
          icon: Icons.flag_outlined,
          text: l10n.eta(_etaTime(status.remainingTime!)),
        ),
      if (status.layerNum != null && status.totalLayers != null)
        _MetaItem(
          icon: Icons.layers_outlined,
          text: '${status.layerNum}/${status.totalLayers}',
        ),
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (name != null)
            Text(
              name,
              style: theme.textTheme.bodyMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress == null
                        ? null
                        : (progress / 100).clamp(0.0, 1.0),
                    minHeight: 6,
                  ),
                ),
              ),
              if (progress != null) ...[
                const SizedBox(width: 10),
                Text(
                  '${progress.toStringAsFixed(0)}%',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ],
          ),
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 14, runSpacing: 4, children: meta),
          ],
        ],
      ),
    );
  }
}

class _MetaItem extends StatelessWidget {
  const _MetaItem({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(text, style: theme.textTheme.bodySmall?.copyWith(color: color)),
      ],
    );
  }
}

/// Siatka kafelków temperatur (2 w rzędzie), każdy z ikoną i parą
/// wartość aktualna / docelowa.
class _TempGrid extends StatelessWidget {
  const _TempGrid({required this.readings});

  final List<_TempReading> readings;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 8.0;
        final tileWidth = (constraints.maxWidth - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final r in readings)
              SizedBox(width: tileWidth, child: _TempTile(reading: r)),
          ],
        );
      },
    );
  }
}

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

    final value = StringBuffer(
      actual == null ? '—' : '${actual.toStringAsFixed(0)}°',
    );
    // Cel pokazujemy tylko gdy ustawiony (>0); 0 = grzanie wyłączone.
    if (target != null && target > 0) {
      value.write(' / ${target.toStringAsFixed(0)}°');
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(reading.icon, size: 14, color: scheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  reading.label(l10n),
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value.toString(),
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({
    required this.label,
    required this.connected,
    this.active = false,
  });

  final String label;
  final bool connected;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Chip(
      visualDensity: VisualDensity.compact,
      backgroundColor: active
          ? scheme.primaryContainer
          : (connected
              ? scheme.secondaryContainer
              : scheme.surfaceContainerHighest),
      label: Text(label, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

enum _TempKind { nozzle, bed, chamber, unknown }

/// Para odczytów (aktualny + docelowy) jednego czujnika. Etykieta jest
/// tłumaczona dopiero przy renderowaniu (z [BuildContext]).
class _TempReading {
  const _TempReading({
    required this.kind,
    required this.raw,
    required this.actual,
    required this.target,
    this.index,
  });

  final _TempKind kind;
  final String raw; // surowy klucz — pokazywany dla nieznanego czujnika
  final int? index; // numer dyszy (np. 2) lub null
  final double? actual;
  final double? target;

  String label(AppLocalizations l10n) => switch (kind) {
        _TempKind.nozzle =>
          index == null ? l10n.tempNozzle : l10n.tempNozzleNumbered('$index'),
        _TempKind.bed => l10n.tempBed,
        _TempKind.chamber => l10n.tempChamber,
        _TempKind.unknown => raw,
      };

  IconData get icon => switch (kind) {
        _TempKind.nozzle => Icons.local_fire_department,
        _TempKind.bed => Icons.iron,
        _TempKind.chamber => Icons.thermostat,
        _TempKind.unknown => Icons.device_thermostat,
      };
}

/// Grupuje surowe klucze temperatur w pary aktualna/docelowa i porządkuje
/// znane czujniki (dysza, stół, komora) przed nieznanymi.
List<_TempReading> _buildReadings(Map<String, double>? temps) {
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
      _readingFor(base, actuals[base], targets[base]),
  ];
}

_TempReading _readingFor(String base, double? actual, double? target) {
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
  );
}

String _durationText(AppLocalizations l10n, int minutes) => minutes < 60
    ? l10n.durationMinutes(minutes)
    : l10n.durationHoursMinutes(minutes ~/ 60, minutes % 60);

/// Godzina zakończenia (ETA) jako HH:mm = teraz + pozostałe minuty.
String _etaTime(int remainingMinutes) {
  final eta = DateTime.now().add(Duration(minutes: remainingMinutes));
  final hh = eta.hour.toString().padLeft(2, '0');
  final mm = eta.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}
