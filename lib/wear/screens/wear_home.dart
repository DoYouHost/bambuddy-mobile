import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../wear_providers.dart';
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
    return Scaffold(
      body: SafeArea(
        child: fleet.when(
          loading: () => const Center(
              child: SizedBox(
                  width: 26, height: 26, child: CircularProgressIndicator())),
          error: (e, _) => _CenterMessage(
            text: l10n.wearConnectionFailed,
            action: () => ref.invalidate(wearFleetProvider),
          ),
          data: (fleet) {
            final printers = fleet.printers;
            if (printers.isEmpty) {
              return _CenterMessage(
                text: l10n.wearNoPrinters,
                action: () => ref.invalidate(wearFleetProvider),
              );
            }
            // Single printer → no picker, land directly on its controls.
            if (printers.length == 1) {
              return WearPrinterControlBody(printerId: printers.first.printer.id);
            }
            return const WearPrinterListBody();
          },
        ),
      ),
    );
  }
}

class _CenterMessage extends StatelessWidget {
  const _CenterMessage({required this.text, required this.action});

  final String text;
  final VoidCallback action;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
                onPressed: action,
                child: Text(AppLocalizations.of(context).retry)),
          ],
        ),
      );
}
