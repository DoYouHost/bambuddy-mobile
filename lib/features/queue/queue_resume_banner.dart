import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_context.dart';
import '../../core/models/queue_item.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import 'queue_providers.dart';
import 'queue_removal.dart';

/// One banner per printer a failed print is holding (`require_previous_success`),
/// over the queue — the web's "Resume after failure" rows (`QueuePage.tsx`, #1818).
/// Without it the skipped jobs sit in the history with no way back short of
/// queueing each one again.
///
/// Absent for a user without `queue:update_all`: [queueSkippedProvider] answers
/// nothing for them, so there is nothing to draw.
class QueueResumeBanners extends ConsumerWidget {
  const QueueResumeBanners({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final skipped = ref.watch(queueSkippedProvider).valueOrNull ?? const [];
    final blocked = gateBlockedPrinters(
      skipped,
      fallbackName: (id) => l10n.statsPrinterFallback('$id'),
    );
    if (blocked.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        for (final printer in blocked) _ResumeBanner(printer: printer),
      ],
    );
  }
}

class _ResumeBanner extends StatelessWidget {
  const _ResumeBanner({required this.printer});

  final GateBlockedPrinter printer;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DashSpace.gutter,
        DashSpace.sm,
        DashSpace.gutter,
        DashSpace.xs,
      ),
      child: logTag(
        'queue.resume_banner',
        Container(
          padding: const EdgeInsets.all(DashSpace.lg),
          decoration: BoxDecoration(
            color: t.accentOrange.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: t.accentOrange.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 20,
                    color: t.accentOrangeInk,
                  ),
                  const SizedBox(width: DashSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.queueResumeBanner(printer.name, printer.skipped),
                          style: t.bodyStrong,
                        ),
                        const SizedBox(height: DashSpace.xs),
                        Text(l10n.queueResumeHint, style: t.labelSoft),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: DashSpace.md),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  style: dashPrimaryButtonStyle(t),
                  onPressed: () => _resume(context),
                  icon: const Icon(Icons.play_circle_outline),
                  label: Text(l10n.queueResumeButton),
                ).tagged('queue.resume'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Asks first: it puts every skipped job on the printer back in line, and the
  /// next one may start as soon as the scheduler looks. The flow outlives the
  /// banner — the next poll that finds the gate down removes it mid-dialog —
  /// so the handles are taken before the first `await` ([detachFrom]).
  Future<void> _resume(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final (:providers, :messenger) = detachFrom(context);
    final confirmed = await confirmDialog(
      context,
      id: 'queue.resume_confirm',
      title: l10n.queueResumeConfirmTitle,
      message: l10n.queueResumeConfirmBody(printer.skipped, printer.name),
      confirmLabel: l10n.queueResumeButton,
    );
    if (!confirmed) return;
    final (:outcome, :restored) = await providers
        .read(queueProvider.notifier)
        .resumeAfterFailure(printer.printerId);
    messenger.snack(
      queueWriteMessage(l10n, outcome) ?? l10n.queueResumed(restored),
    );
  }
}
