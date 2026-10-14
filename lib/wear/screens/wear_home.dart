import 'dart:async';

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

  /// Once per process: Android shows the prompt at most twice anyway, and a
  /// second ask on every poll would be a dialog over the screen the user is
  /// looking at.
  static bool _askedForNotifications = false;

  @visibleForTesting
  static void forgetNotificationAsk() => _askedForNotifications = false;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fleet = ref.watch(wearFleetProvider);
    // Asked on the screen with a running print, before the app goes to the
    // background — where the Ongoing Activity needs it and nothing can ask.
    // Read off every frame rather than listened for: a cached fleet is there
    // before any change, and the user may leave before the first poll.
    final running =
        fleet.drawable?.printers.any((p) => p.status?.isPrinting ?? false) ??
        false;
    if (running && !_askedForNotifications) {
      _askedForNotifications = true;
      unawaited(ref.read(wearOngoingProvider).requestPermission());
    }
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
