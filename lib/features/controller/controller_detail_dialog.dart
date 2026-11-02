import 'dart:math' as math;

import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/dash_theme.dart';
import 'controller_controls.dart';
import 'scale_to_fit.dart';

/// Opens a Prints item's dialog, scaled like the controller body: the scale is
/// read here, under the body, because the dialog's route is not.
Future<T?> showControllerDetailDialog<T>(
  BuildContext context,
  Widget Function(double scale) builder,
) {
  final scale = ControllerScale.of(context);
  return showDialog<T>(context: context, builder: (_) => builder(scale));
}

/// One thing known of an item: what it is told by, and its value.
class ControllerFact {
  const ControllerFact(this.icon, this.text, {this.ink, this.fill});

  final IconData icon;
  final String text;

  /// A fact in a colour of its own — a model this printer cannot take, how a
  /// print ended. Null is the plain one.
  final Color? ink;

  /// The pill's own tint, where the colour as text is a darker shade of it
  /// (the warning in the light theme). Defaults to [ink].
  final Color? fill;
}

/// The frame of a Prints item's dialog: thumbnail, name and close, the facts,
/// why the main action is off, and the actions.
///
/// An action that leads into another flow closes the dialog with a choice, and
/// the caller runs it once the dialog is gone: started from inside, the flow
/// would open its own dialogs over this one and leave it standing over an item
/// that may be gone. An action that finishes in place — a file's delete — runs
/// with [busy] set.
class ControllerDetailDialog extends StatelessWidget {
  const ControllerDetailDialog({
    super.key,
    required this.scale,
    required this.closeId,
    required this.thumbnail,
    required this.title,
    required this.facts,
    this.reason,
    this.actions = const [],
    this.busy = false,
  });

  /// The size the content is laid out for, before the whole is scaled to the
  /// room the screen gives it.
  static const width = 560.0;
  static const height = 260.0;
  static const thumbSize = 148.0;

  final double scale;
  final String closeId;
  final Widget thumbnail;
  final String title;
  final List<ControllerFact> facts;
  final String? reason;

  /// Laid out side by side, each taking an equal share of the row.
  final List<Widget> actions;

  /// A request is under way: the close icon answers nothing meanwhile.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(DashSpace.md),
      child: LayoutBuilder(
        builder: (context, box) => SizedBox(
          width: math.min(width * scale, box.maxWidth),
          height: math.min(height * scale, box.maxHeight),
          child: ScaleToFit(
            minSize: const Size(width, height),
            child: Padding(
              padding: const EdgeInsets.all(DashSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(DashSpace.md),
                          child: thumbnail,
                        ),
                        const SizedBox(width: DashSpace.lg),
                        Expanded(child: _details(context, t)),
                      ],
                    ),
                  ),
                  if (reason case final why?) ...[
                    Text(
                      why,
                      style: t.bodySoft.copyWith(color: t.warningInk),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: DashSpace.sm),
                  ],
                  if (actions.isNotEmpty)
                    Row(
                      children: [
                        for (final (i, action) in actions.indexed) ...[
                          if (i > 0) const SizedBox(width: DashSpace.md),
                          Expanded(child: action),
                        ],
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _details(BuildContext context, DashTokens t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                title,
                style: t.titleMd,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            logTag(
              closeId,
              IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                color: t.textPrimary,
                icon: const Icon(Icons.close_rounded),
                onPressed: busy ? null : () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
        const SizedBox(height: DashSpace.sm),
        // The room left under the title, scrolled when a job carries more
        // facts than it holds beside a two-line reason.
        Expanded(
          child: SingleChildScrollView(
            child: Wrap(
              spacing: DashSpace.sm,
              runSpacing: DashSpace.sm,
              children: [for (final fact in facts) _FactPill(fact)],
            ),
          ),
        ),
      ],
    );
  }
}

/// An action of a [ControllerDetailDialog], at the controller's button height.
/// A [tone] colours it; without one it is the plain wash.
class ControllerDialogAction extends StatelessWidget {
  const ControllerDialogAction({
    super.key,
    required this.id,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.tone,
    this.ink,
  });

  final String id;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? tone;
  final Color? ink;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    // A disabled action drops its colour: an accent that answers nothing reads
    // as a button that is broken.
    final enabled = onPressed != null;
    return logTag(
      id,
      FilledButton.icon(
        style: controllerButtonStyle(
          t,
          minimumSize: const Size(0, controllerButtonHeight),
          tone: enabled ? tone : null,
          ink: enabled ? ink : null,
        ),
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
      ),
    );
  }
}

class _FactPill extends StatelessWidget {
  const _FactPill(this.fact);

  final ControllerFact fact;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final tint = fact.fill ?? fact.ink;
    final ink = fact.ink ?? t.textSecondary;
    final radius = BorderRadius.circular(DashSpace.sm);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DashSpace.sm,
        vertical: DashSpace.xs,
      ),
      decoration: BoxDecoration(
        color: tint == null ? t.subCard : tint.withValues(alpha: 0.14),
        borderRadius: radius,
        border: Border.all(
          color: tint == null ? t.subCardBorder : tint.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(fact.icon, size: DashSpace.lg, color: ink),
          const SizedBox(width: DashSpace.xs),
          // A server's waiting reason or a long user name is wider than the
          // pill can grow.
          Flexible(
            child: Text(
              fact.text,
              style: t.monoLabel.copyWith(color: ink),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
