import 'package:flutter/material.dart';

import '../../../data/printers_repository.dart';

/// Przyjazne etykiety typowych kluczy temperatur; serwer nie dokumentuje
/// zestawu, więc nieznane klucze pokazujemy z surową nazwą.
const _tempLabels = {
  'nozzle': 'Dysza',
  'nozzle_temper': 'Dysza',
  'bed': 'Stół',
  'bed_temper': 'Stół',
  'chamber': 'Komora',
  'chamber_temper': 'Komora',
};

class PrinterCard extends StatelessWidget {
  const PrinterCard({super.key, required this.item});

  final PrinterWithStatus item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = item.status;
    final connected = status?.connected ?? false;
    final progress = status?.progress;
    final printing = status?.isPrinting ?? false;

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
                      ? 'status niedostępny'
                      : (status.state ?? (connected ? 'online' : 'offline')),
                  connected: connected,
                ),
              ],
            ),
            if (printing) ...[
              const SizedBox(height: 10),
              if (status?.currentPrint != null ||
                  status?.gcodeFile != null)
                Text(
                  status?.currentPrint ?? status!.gcodeFile!,
                  style: theme.textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: progress == null
                    ? null
                    : (progress / 100).clamp(0.0, 1.0),
              ),
              const SizedBox(height: 4),
              Text(
                [
                  if (progress != null) '${progress.toStringAsFixed(0)}%',
                  if (status?.layerNum != null &&
                      status?.totalLayers != null)
                    'warstwa ${status!.layerNum}/${status.totalLayers}',
                  if (status?.remainingTime != null)
                    'pozostało ${_formatMinutes(status!.remainingTime!)}',
                ].join(' · '),
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (status?.temperatures?.isNotEmpty ?? false) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final entry in status!.temperatures!.entries)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text(
                        '${_tempLabels[entry.key] ?? entry.key}: '
                        '${entry.value.toStringAsFixed(0)}°C',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.label, required this.connected});

  final String label;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Chip(
      visualDensity: VisualDensity.compact,
      backgroundColor: connected
          ? scheme.primaryContainer
          : scheme.surfaceContainerHighest,
      label: Text(label, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

String _formatMinutes(int minutes) {
  if (minutes < 60) return '$minutes min';
  return '${minutes ~/ 60} h ${minutes % 60} min';
}
