import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/printer_status.dart';
import '../../core/notifications/hms_catalog.dart';
import '../../core/settings/controller_prefs.dart';
import '../../data/printers_repository.dart';
import '../../providers.dart';
import '../dashboard/providers.dart';
import '../dashboard/ws_providers.dart';

/// The controller's settings on this device.
final controllerPrefsProvider =
    NotifierProvider<ControllerPrefsNotifier, ControllerPrefs>(
      ControllerPrefsNotifier.new,
    );

class ControllerPrefsNotifier extends Notifier<ControllerPrefs> {
  @override
  ControllerPrefs build() =>
      ref.watch(settingsRepositoryProvider).loadControllerPrefs();

  /// State first, then disk: two settings changed in quick succession must each
  /// start from the other's result, not from what was on disk before either.
  Future<void> update(ControllerPrefs Function(ControllerPrefs) change) async {
    state = change(state);
    await ref.read(settingsRepositoryProvider).saveControllerPrefs(state);
  }
}

/// The printer a controller was opened for. [rosterKnown] tells "the roster has
/// not arrived yet" from "it arrived and this printer is not in it".
typedef ControllerPrinter = ({bool rosterKnown, PrinterWithStatus? item});

/// **The one place the controller is scoped to its printer.** Every other
/// provider and widget of the controller reads through here, so a fault, a
/// status or an event of any other printer cannot reach it
/// ([docs/single-printer-controller.md] §1).
///
/// The live status goes over the roster's, as on the dashboard: the roster alone
/// is polled once a minute while the socket is up.
final controllerPrinterProvider = Provider.autoDispose
    .family<ControllerPrinter, int>((ref, printerId) {
      final roster = ref.watch(dashboardProvider.select((s) => s.printers));
      if (roster == null) return (rosterKnown: false, item: null);
      final live = ref.watch(
        printerStatusesProvider.select((statuses) => statuses[printerId]),
      );
      for (final p in roster) {
        if (p.printer.id != printerId) continue;
        return (
          rosterKnown: true,
          item: live == null
              ? p
              : PrinterWithStatus(printer: p.printer, status: live),
        );
      }
      return (rosterKnown: true, item: null);
    });

/// The printer's active HMS errors, as the dashboard card would list them — none
/// for a printer that is not connected, whose codes are last-known.
final controllerErrorsProvider = Provider.autoDispose
    .family<List<HmsError>, int>(
      (ref, printerId) => displayableHmsErrors(
        ref.watch(controllerPrinterProvider(printerId)).item?.status,
        describe: HmsCatalog.instance.describe,
      ),
    );
