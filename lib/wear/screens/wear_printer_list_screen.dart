import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../wear_providers.dart';
import '../wear_status.dart';
import '../wear_theme.dart';
import '../widgets/wear_header.dart';
import '../widgets/wear_scroll_view.dart';
import '../widgets/wear_settings_entry.dart';
import '../widgets/wear_spinner.dart';
import 'wear_printer_control_screen.dart';

/// Printer picker (shown only when more than one printer). Tapping a row pushes
/// its control screen.
class WearPrinterListBody extends ConsumerWidget {
  const WearPrinterListBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fleet = ref.watch(wearFleetProvider).drawable;
    final printers = fleet?.printers ?? const [];
    return wearDimIfStale(
      stale: fleet?.stale ?? false,
      child: WearScrollView(
        curved: true,
        onRefresh: () => ref.read(wearFleetProvider.notifier).refresh(),
        children: [
          WearHeader(AppLocalizations.of(context).printersTitle),
          const SizedBox(height: WearSpace.titleToContent),
          // Same sentence the control screen carries, for the same reason: a
          // dimmed list with nothing to explain it reads as a rendering fault.
          // Rows stay tappable — this screen only navigates, and the control
          // screen it opens does its own gating.
          if (fleet?.stale ?? false) ...[
            Text(
              AppLocalizations.of(context).wearWaitingForState,
              textAlign: TextAlign.center,
              style: WearText.body.copyWith(color: wearInert),
            ),
            const SizedBox(height: DashSpace.sm),
          ],
          for (final (i, p) in printers.indexed) ...[
            if (i > 0) const SizedBox(height: WearSpace.inGroup),
            _PrinterRow(
              name: p.printer.name,
              stateLabel: wearStateOf(
                p.status,
              ).label(AppLocalizations.of(context)),
              stateColor: wearStateOf(p.status).color,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      WearPrinterControlScreen(printerId: p.printer.id),
                ),
              ),
            ),
          ],
          const SizedBox(height: WearSpace.betweenGroups),
          const WearSettingsEntry(),
        ],
      ),
    );
  }
}

class _PrinterRow extends StatelessWidget {
  const _PrinterRow({
    required this.name,
    required this.stateLabel,
    required this.stateColor,
    required this.onTap,
  });

  final String name;
  final String stateLabel;
  final Color stateColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: wearSurface,
    borderRadius: BorderRadius.circular(wearRadiusRow),
    child: InkWell(
      // The same radius twice is not a repetition to fold away: Material
      // clips the fill and InkWell clips the splash, and a splash with
      // squarer corners than the row it lands in is what a literal here
      // used to drift into.
      borderRadius: BorderRadius.circular(wearRadiusRow),
      onTap: onTap,
      // A Wear Material 3 tonal button with a second line: its height, inset
      // and the two label styles.
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: wearButtonHeight),
        child: Padding(
          padding: wearButtonPadding,
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: stateColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: DashSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: wearButtonLabel,
                    ),
                    // One line, like the name above it. Without this the
                    // row grows a second line for any state whose label does
                    // not fit — "Oczekiwanie na płytę" is 20 characters in a
                    // ~100 dp column — and 16 dp of a 75 dp row is a lot to
                    // spend on a wrapped word nobody needs to read twice.
                    Text(
                      stateLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: wearButtonSecondaryLabel.copyWith(
                        color: stateColor,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 18),
            ],
          ),
        ),
      ),
    ),
  );
}
