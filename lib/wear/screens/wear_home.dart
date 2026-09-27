import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../wear_providers.dart';
import '../widgets/wear_center_message.dart';
import '../widgets/wear_screen.dart';
import 'wear_printer_control_screen.dart';
import 'wear_printer_list_screen.dart';

/// Decides the first screen once a profile exists: skip straight to the control
/// screen when there's a single printer, otherwise show the picker.
class WearHome extends ConsumerWidget {
  const WearHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fleet = ref.watch(wearFleetProvider);
    final l10n = AppLocalizations.of(context);
    return WearScreen(
      child: fleet.when(
        loading: () => const Center(
          child: SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(),
          ),
        ),
        error: (e, _) => WearCenterMessage(
          text: l10n.wearConnectionFailed,
          onRetry: () => ref.invalidate(wearFleetProvider),
        ),
        data: (fleet) {
          final printers = fleet.printers;
          if (printers.isEmpty) {
            return WearCenterMessage(
              text: l10n.wearNoPrinters,
              onRetry: () => ref.invalidate(wearFleetProvider),
            );
          }
          // Single printer → no picker, land directly on its controls.
          if (printers.length == 1) {
            return WearPrinterControlBody(
              printerId: printers.first.printer.id,
              showSettings: true,
            );
          }
          return const WearPrinterListBody();
        },
      ),
    );
  }
}
