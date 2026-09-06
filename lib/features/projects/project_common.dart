import 'package:flutter/material.dart';

import '../../core/diagnostics/log_tag.dart';
import '../../core/theme/dash_text.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';

/// Known project statuses. The server stores a free string, so the UI offers
/// this fixed set but renders unknown values gracefully (raw text, neutral color).
const projectStatusValues = [
  'planning',
  'active',
  'on_hold',
  'completed',
  'archived',
];

const projectPriorityValues = ['low', 'normal', 'high', 'urgent'];

/// Predefined project color swatches — the exact 7-color palette from the web
/// UI (Material 500 hues). The picker offers only these.
const projectColorPalette = [
  '#f44336', // red
  '#ff9800', // orange
  '#ffeb3b', // yellow
  '#4caf50', // green
  '#2196f3', // blue
  '#9c27b0', // purple
  '#607d8b', // gray
];

String projectStatusLabel(AppLocalizations l10n, String status) =>
    switch (status) {
      'planning' => l10n.projectStatusPlanning,
      'active' => l10n.projectStatusActive,
      'on_hold' => l10n.projectStatusOnHold,
      'completed' => l10n.projectStatusCompleted,
      'archived' => l10n.projectStatusArchived,
      _ => status,
    };

String projectPriorityLabel(AppLocalizations l10n, String priority) =>
    switch (priority) {
      'low' => l10n.projectPriorityLow,
      'normal' => l10n.projectPriorityNormal,
      'high' => l10n.projectPriorityHigh,
      'urgent' => l10n.projectPriorityUrgent,
      _ => priority,
    };

/// Status accent color, from the Dash design tokens.
Color projectStatusColor(DashTokens t, String status) => switch (status) {
  'active' => t.accentGreenInk,
  'completed' => t.accentBlue,
  'on_hold' => t.accentOrangeInk,
  'archived' => t.textTertiary,
  _ => t.textTertiary,
};

/// Parse a hex color string (`#RRGGBB`, `RRGGBB`, or `#RRGGBBAA`) to a [Color].
/// Returns null when missing or malformed.
Color? parseProjectColor(String? hex) {
  if (hex == null) return null;
  var s = hex.trim();
  if (s.startsWith('#')) s = s.substring(1);
  if (s.length == 8) {
    // Original input is RRGGBBAA → reorder to AARRGGBB for Color.
    s = s.substring(6, 8) + s.substring(0, 6);
  } else if (s.length == 6) {
    // Opaque RGB → prepend full alpha (already AARRGGBB).
    s = 'FF$s';
  }
  final value = int.tryParse(s, radix: 16);
  return value == null ? null : Color(value);
}

/// Small colored dot used in list cards and chips.
class ProjectColorDot extends StatelessWidget {
  const ProjectColorDot({super.key, required this.color, this.size = 12});

  final String? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final c = parseProjectColor(color) ?? t.textTertiary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c,
        shape: BoxShape.circle,
        border: Border.all(color: t.cardBorder, width: 1),
      ),
    );
  }
}

/// Row of predefined color swatches with single selection (plus a "none"
/// option). Stores/returns the chosen hex as `#RRGGBB`, or null for none.
class ProjectColorSelector extends StatelessWidget {
  const ProjectColorSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final String? selected;
  final ValueChanged<String?> onChanged;

  bool _matches(String hex) =>
      (selected ?? '').toUpperCase().endsWith(hex.substring(1));

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        // "None" option.
        _swatch(
          context,
          color: t.subCard,
          isSelected: selected == null,
          onTap: () => onChanged(null),
          child: Icon(
            Icons.format_color_reset_outlined,
            size: 18,
            color: t.textSecondary,
          ),
        ),
        for (final hex in projectColorPalette)
          _swatch(
            context,
            color: parseProjectColor(hex)!,
            isSelected: _matches(hex),
            onTap: () => onChanged(hex),
          ),
      ],
    );
  }

  Widget _swatch(
    BuildContext context, {
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
    Widget? child,
  }) {
    final t = DashTokens.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? t.textPrimary : t.subCardBorder,
            width: isSelected ? 3 : 1,
          ),
        ),
        child: child,
      ),
    ).tagged('project_form.color');
  }
}

/// Compact status chip.
class ProjectStatusChip extends StatelessWidget {
  const ProjectStatusChip({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final color = projectStatusColor(t, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        projectStatusLabel(l10n, status),
        style: t.micro.copyWith(color: color, letterSpacing: 0.2),
      ),
    );
  }
}

/// Format a progress fraction (server sends 0..100) as a 0..1 value for bars.
double progressFraction(double? percent) {
  if (percent == null) return 0;
  return (percent / 100).clamp(0, 1).toDouble();
}
