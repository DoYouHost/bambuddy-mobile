import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter/material.dart';

import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import 'controller_controls.dart';
import 'controller_files.dart';

/// The three views of the Prints tab, chosen on its rail.
enum ControllerPrintsView {
  files,
  queue,
  archive;

  String label(AppLocalizations l10n) => switch (this) {
    ControllerPrintsView.files => l10n.controllerTabFiles,
    ControllerPrintsView.queue => l10n.navQueue,
    ControllerPrintsView.archive => l10n.navArchive,
  };

  IconData get icon => switch (this) {
    ControllerPrintsView.files => Icons.folder_rounded,
    ControllerPrintsView.queue => Icons.format_list_numbered_rounded,
    ControllerPrintsView.archive => Icons.history_rounded,
  };

  /// Wire value of the control's diagnostic id; never localized.
  String get logId => switch (this) {
    ControllerPrintsView.files => 'controller.prints.files',
    ControllerPrintsView.queue => 'controller.prints.queue',
    ControllerPrintsView.archive => 'controller.prints.archive',
  };
}

/// The rail takes width, which a phone held sideways has to spare, and leaves
/// each view the whole height.
const _railWidth = 96.0;

/// The Prints tab: what this printer can print, what waits for it and what it
/// printed ([docs/single-printer-controller.md] §8). The screen keeps [view], so
/// a visit to another tab comes back to the same one.
class ControllerPrints extends StatelessWidget {
  const ControllerPrints({
    super.key,
    required this.printerId,
    required this.view,
    required this.onView,
  });

  final int printerId;
  final ControllerPrintsView view;
  final ValueChanged<ControllerPrintsView> onView;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: _railWidth,
          child: _Rail(view: view, onView: onView),
        ),
        const SizedBox(width: DashSpace.sm),
        Expanded(
          child: switch (view) {
            ControllerPrintsView.files => ControllerFiles(printerId: printerId),
            ControllerPrintsView.queue ||
            ControllerPrintsView.archive => const SizedBox.shrink(),
          },
        ),
      ],
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({required this.view, required this.onView});

  final ControllerPrintsView view;
  final ValueChanged<ControllerPrintsView> onView;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, candidate) in ControllerPrintsView.values.indexed) ...[
          if (i > 0) const SizedBox(height: DashSpace.sm),
          Expanded(
            child: logTag(
              candidate.logId,
              FilledButton(
                style: controllerButtonStyle(
                  t,
                  padding: const EdgeInsets.all(DashSpace.xs),
                  tone: candidate == view ? t.accentGreen : null,
                  ink: candidate == view ? t.accentGreenInk : null,
                ),
                onPressed: () => onView(candidate),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(candidate.icon),
                    const SizedBox(height: DashSpace.xs),
                    Text(
                      candidate.label(l10n),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              selected: candidate == view,
            ),
          ),
        ],
      ],
    );
  }
}
