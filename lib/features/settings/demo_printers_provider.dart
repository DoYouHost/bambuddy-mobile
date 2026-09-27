import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/demo/demo_backend.dart';
import '../../core/notifications/background_sync.dart';
import '../../providers.dart';

/// How many printers the demo runs a print on.
///
/// Demo only, and it exists for one reason: everything that behaves differently
/// with several machines printing — the dashboard summary, the ongoing
/// notification's average — had no way to be looked at, because the demo has
/// always printed on exactly one.
///
/// The value lives in three places at once and all three are set here: the
/// preference (so it survives a restart), this isolate's [DemoBackend], and the
/// service isolate's, which runs its own copy of the demo and draws the
/// notification from it.
final demoPrintingCountProvider =
    NotifierProvider<DemoPrintingCountNotifier, int>(
      DemoPrintingCountNotifier.new,
    );

class DemoPrintingCountNotifier extends Notifier<int> {
  @override
  int build() {
    final count = ref.watch(settingsRepositoryProvider).loadDemoPrintingCount();
    DemoBackend.printingPrinters = count;
    return count;
  }

  /// What the demo shows while the slider is being dragged.
  ///
  /// Nothing is written and nothing crosses to the service isolate: a drag
  /// produces a value per frame, and each one would be a flash write and an
  /// IPC message. The dashboard still follows along, because the poke is in
  /// this isolate and costs nothing.
  void preview(int count) {
    DemoBackend.printingPrinters = count;
    // The dashboard is fed by the fake socket, which would otherwise show this
    // at its next three-second tick.
    DemoBackend.pokeSockets();
    state = count;
  }

  /// The value the user settled on: kept, and told to the service isolate,
  /// which runs its own copy of the demo and draws the notification from it.
  Future<void> set(int count) async {
    preview(count);
    await ref.read(settingsRepositoryProvider).saveDemoPrintingCount(count);
    ref.read(backgroundMonitorProvider).sync(BackgroundSync.demoPrinters);
  }
}
