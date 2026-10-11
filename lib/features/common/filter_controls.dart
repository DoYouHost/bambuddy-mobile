import 'package:flutter/material.dart';

import 'package:app_diagnostics/app_diagnostics.dart';
import '../../core/theme/dash_theme.dart';

/// Square button opening a list screen's filter sheet; the badge shows how many
/// filters are active. Size matches the search field (48×48) so the two line up
/// in the same row.
class FilterButton extends StatelessWidget {
  const FilterButton({
    super.key,
    required this.count,
    required this.tooltip,
    required this.id,
    required this.onTap,
  });

  final int count;
  final String tooltip;

  /// Diagnostic identifier of the button, e.g. `archive.filters`.
  final String id;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final active = count > 0;
    return Tooltip(
      message: tooltip,
      child: Badge(
        isLabelVisible: active,
        label: Text('$count'),
        backgroundColor: t.accentGreen,
        textColor: t.onAccent,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Material(
            color: active ? t.accentGreen.withValues(alpha: 0.16) : t.subCard,
            borderRadius: BorderRadius.circular(16),
            child: logTag(
              id,
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: onTap,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: active
                          ? t.accentGreen.withValues(alpha: 0.4)
                          : t.subCardBorder,
                    ),
                  ),
                  child: Icon(
                    Icons.tune,
                    color: active ? t.accentGreenInk : t.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Heading above one group of filter chips inside a filter sheet.
class FilterGroupLabel extends StatelessWidget {
  const FilterGroupLabel({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: DashSpace.sm),
      child: Text(label, style: t.bodyBold),
    );
  }
}
