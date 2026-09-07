import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

/// Pieces shared by the two sensor-history sheets (AMS units and printer
/// heaters), which differ only in the series they plot.

/// Thins a recorded series down to at most [budget] points, always keeping the
/// newest one (the stat row reads "current" off it).
///
/// Both recorders sample once a minute, so the 7-day window is ~10k points —
/// more than the chart is wide in pixels, and every one of them is a spot
/// fl_chart curves, fills and hit-tests. Decimating by stride rather than
/// averaging keeps real recorded values on screen, and the true extremes are
/// still shown: min/max/avg above the chart come from the server, computed over
/// every sample in the window.
List<T> thinnedForChart<T>(List<T> points, {int budget = 480}) {
  if (points.length <= budget) return points;
  final stride = (points.length / budget).ceil();
  return [
    for (var i = 0; i < points.length; i += stride) points[i],
    if ((points.length - 1) % stride != 0) points.last,
  ];
}

/// Compact segmented time-range picker (its own row so it wraps independently
/// of the metric toggle on narrow screens).
class HistoryRangeSelector extends StatelessWidget {
  const HistoryRangeSelector({
    super.key,
    required this.ranges,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
  });

  final List<int> ranges;
  final int selected;
  final String Function(int hours) labelOf;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<int>(
      showSelectedIcon: false,
      segments: [
        for (final h in ranges)
          ButtonSegment(value: h, label: Text(labelOf(h))),
      ],
      selected: {selected},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

/// One labelled figure in the row above a history chart (current / avg / …).
class HistoryStat extends StatelessWidget {
  const HistoryStat({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

/// Label of a history window in the range picker. The four values are the ones
/// the sheets offer; anything else reads as the 24 h default.
String sensorRangeLabel(AppLocalizations l10n, int hours) => switch (hours) {
  6 => l10n.sensorHistoryRange6h,
  48 => l10n.sensorHistoryRange48h,
  168 => l10n.sensorHistoryRange7d,
  _ => l10n.sensorHistoryRange24h,
};
