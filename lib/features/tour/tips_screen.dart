import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import 'tour_screen.dart';

/// Every gesture the app hides, in one place, and the way back into the tour.
class TipsScreen extends StatelessWidget {
  const TipsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tips = [
      (
        Icons.edit_outlined,
        l10n.tipsEditPrinterTitle,
        l10n.tipsEditPrinterBody,
      ),
      (Icons.drag_indicator, l10n.tipsReorderTitle, l10n.tipsReorderBody),
      (Icons.swipe_left_outlined, l10n.tipsSwipeTitle, l10n.tipsSwipeBody),
      (Icons.checklist_rounded, l10n.tipsSelectTitle, l10n.tipsSelectBody),
      (Icons.zoom_in_rounded, l10n.tipsZoomTitle, l10n.tipsZoomBody),
      (Icons.content_cut_rounded, l10n.tipsTrimTitle, l10n.tipsTrimBody),
      (Icons.view_quilt_outlined, l10n.tipsWallTitle, l10n.tipsWallBody),
    ];
    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: dashAppBar(context, title: l10n.tipsTitle),
        body: ListView(
          padding: screenListPadding(context),
          children: [
            FilledButton.icon(
              onPressed: () => TourHost.open(context),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(l10n.tipsRunTour),
            ).tagged('tips.run_tour'),
            const SizedBox(height: DashSpace.xl),
            SettingsCard(
              rows: [
                for (final (icon, title, body) in tips)
                  _TipRow(icon: icon, title: title, body: body),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TipRow extends StatelessWidget {
  const _TipRow({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Padding(
      padding: const EdgeInsets.all(DashSpace.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: t.accentGreenInk),
          const SizedBox(width: DashSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.bodyStrong),
                const SizedBox(height: DashSpace.xs),
                Text(body, style: t.bodySoft),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
