import 'package:flutter/material.dart';

import '../../core/diagnostics/log_tag.dart';

/// Shared "failed to load, tap to retry" view. Replaces the per-screen
/// `_ErrorView` copies (queue, archive, maintenance, inventory, projects,
/// files, stats, gcode) that were all minor variants of this.
class AsyncErrorView extends StatelessWidget {
  const AsyncErrorView({
    super.key,
    required this.message,
    required this.onRetry,
    required this.retryLabel,
    this.icon = Icons.cloud_off,
    this.tonal = false,
    this.scrollable = false,
  });

  final String message;
  final VoidCallback onRetry;
  final String retryLabel;

  /// Leading glyph; null hides it (e.g. inventory's compact variant).
  final IconData? icon;

  /// Use a tonal button instead of the filled default.
  final bool tonal;

  /// Wrap in a scrollable so an enclosing `RefreshIndicator` can pull-to-retry.
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 48), const SizedBox(height: 12)],
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(message, textAlign: TextAlign.center),
        ),
        const SizedBox(height: 12),
        tonal
            ? FilledButton.tonal(onPressed: onRetry, child: Text(retryLabel)).tagged('error.retry')
            : FilledButton(onPressed: onRetry, child: Text(retryLabel)).tagged('error.retry'),
      ],
    );

    if (scrollable) {
      return ListView(
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.6,
            child: Center(child: content),
          ),
        ],
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: content,
      ),
    );
  }
}

/// Shared empty-state view (icon + centered message). Built as a `ListView` so
/// an enclosing `RefreshIndicator` still works while the list is empty.
/// Replaces the per-screen `_EmptyView` copies.
class EmptyStateView extends StatelessWidget {
  const EmptyStateView({super.key, required this.message, required this.icon});

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(48),
          child: Column(
            children: [
              Icon(icon, size: 48, color: Theme.of(context).disabledColor),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
            ],
          ),
        ),
      ],
    );
  }
}
