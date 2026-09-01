import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../wear_providers.dart';
import '../wear_status.dart';
import '../wear_theme.dart';
import '../widgets/wear_header.dart';
import '../widgets/wear_scroll_view.dart';
import '../widgets/wear_settings_entry.dart';
import 'wear_printer_control_screen.dart';

/// Printer picker (shown only when more than one printer). Tapping a row pushes
/// its control screen.
class WearPrinterListBody extends ConsumerWidget {
  const WearPrinterListBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fleet = ref.watch(wearFleetProvider);
    final printers = fleet.valueOrNull?.printers ?? const [];
    return WearScrollView(
      // Uniform short rows, which is exactly what curving is for: the picker
      // was handing 36% of the face to a margin nothing could ever enter.
      curved: true,
      onRefresh: () => ref.read(wearFleetProvider.notifier).refresh(),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: WearHeader(AppLocalizations.of(context).printersTitle),
        ),
        for (final p in printers)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: _PrinterRow(
              name: p.printer.name,
              stateLabel: wearStateOf(p.status).label(
                AppLocalizations.of(context),
              ),
              stateColor: wearStateOf(p.status).color,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => WearPrinterControlScreen(
                    printerId: p.printer.id,
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 4),
        const WearSettingsEntry(),
      ],
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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration:
                      BoxDecoration(color: stateColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: WearText.strong),
                      // One line, like the name above it. Without this the
                      // row grows a second line for any state whose label does
                      // not fit — "Oczekiwanie na płytę" is 20 characters in a
                      // ~100 dp column — and 16 dp of a 75 dp row is a lot to
                      // spend on a wrapped word nobody needs to read twice.
                      Text(stateLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: WearText.small.copyWith(color: stateColor)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 18),
              ],
            ),
          ),
        ),
      );
}
