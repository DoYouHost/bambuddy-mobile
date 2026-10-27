import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_context.dart';
import '../../core/models/current_user.dart';
import '../../core/models/queue_item.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import 'queue_providers.dart';
import 'queue_removal.dart';

/// One banner per printer a failed print is holding (`require_previous_success`),
/// over the queue — the web's "Resume after failure" rows (`QueuePage.tsx`, #1818).
/// Without it the skipped jobs sit in the history with no way back short of
/// queueing each one again. Then one per model whose "any printer" jobs wait
/// because the last print failed on every free printer of it: those are not
/// skipped, so only their waiting reason shows the hold.
///
/// Absent for a user without `queue:update_all`, which both routes ask for:
/// [queueSkippedProvider] answers nothing for them, and the model rows are not
/// read.
class QueueResumeBanners extends ConsumerWidget {
  const QueueResumeBanners({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final skipped = ref.watch(queueSkippedProvider).value ?? const [];
    final printers = gateBlockedPrinters(
      skipped,
      fallbackName: (id) => l10n.statsPrinterFallback('$id'),
    );
    final models = ref.watch(permissionProvider(Permissions.queueUpdateAll))
        ? gateBlockedModels(ref.watch(queueProvider).value ?? const [])
        : const <GateBlockedModel>[];
    if (printers.isEmpty && models.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        for (final printer in printers)
          _ResumeBanner(
            message: l10n.queueResumeBanner(printer.name, printer.skipped),
            confirmBody: l10n.queueResumeConfirmBody(
              printer.skipped,
              printer.name,
            ),
            resume: (providers, messenger) async {
              final (:outcome, :restored) = await providers
                  .read(queueProvider.notifier)
                  .resumeAfterFailure(printer.printerId);
              messenger.snack(
                queueWriteMessage(l10n, outcome) ?? l10n.queueResumed(restored),
              );
            },
          ),
        for (final m in models)
          _ResumeBanner(
            message: l10n.queueResumeModelBanner(m.model, m.waiting),
            confirmBody: l10n.queueResumeModelConfirmBody(m.model),
            resume: (providers, messenger) async {
              final outcome = await providers
                  .read(queueProvider.notifier)
                  .resumeModelAfterFailure(m.model);
              // Nothing is restored here: the jobs never left the queue.
              messenger.snack(
                queueWriteMessage(l10n, outcome) ?? l10n.queueResumed(0),
              );
            },
          ),
      ],
    );
  }
}

class _ResumeBanner extends StatelessWidget {
  const _ResumeBanner({
    required this.message,
    required this.confirmBody,
    required this.resume,
  });

  final String message;
  final String confirmBody;

  /// Sends the resume and says how it went, on handles that outlive the banner.
  final Future<void> Function(
    ProviderContainer providers,
    ScaffoldMessengerState messenger,
  )
  resume;

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
          padding: const EdgeInsets.fromLTRB(
            DashSpace.md,
            DashSpace.xs,
            DashSpace.xs,
            DashSpace.xs,
          ),
          decoration: BoxDecoration(
            color: t.accentOrange.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: t.accentOrange.withValues(alpha: 0.35)),
          ),
          // One line and one word on the button: what happened and what to do
          // about it. The confirmation says the rest.
          child: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 20,
                color: t.accentOrangeInk,
              ),
              const SizedBox(width: DashSpace.sm),
              Expanded(child: Text(message, style: t.bodySoft)),
              TextButton(
                onPressed: () => _resume(context),
                style: TextButton.styleFrom(foregroundColor: t.accentOrangeInk),
                child: Text(l10n.queueResumeButton),
              ).tagged('queue.resume'),
            ],
          ),
        ),
      ),
    );
  }

  /// Asks first: the next held job may start as soon as the scheduler looks. The flow outlives the
  /// banner — the next poll that finds the gate down removes it mid-dialog —
  /// so the handles are taken before the first `await` ([detachFrom]).
  Future<void> _resume(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final (:providers, :messenger) = detachFrom(context);
    final confirmed = await confirmDialog(
      context,
      id: 'queue.resume_confirm',
      title: l10n.queueResumeConfirmTitle,
      message: confirmBody,
      confirmLabel: l10n.queueResumeButton,
    );
    if (!confirmed) return;
    await resume(providers, messenger);
  }
}
