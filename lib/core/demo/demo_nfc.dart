import 'dart:async';

import '../nfc/nfc_reader.dart';

/// The tag of the first demo spool (PLA Basic Black), in the form the reader
/// emits it ([normalizeTagUid]).
const demoNfcSpoolTag = '04A1B2C3D4E5F6';

/// A tag no demo spool carries.
const demoNfcStrangerTag = '04FFEEDDCCBBAA';

/// The phone's NFC in demo mode, which shows every feature on a device that has
/// none (an emulator) and without a spool to hold to it: NFC is on, a tag nobody
/// knows is "held" after [delay], and after another [delay] the first demo
/// spool's. Listening again starts the two over.
class DemoNfcReader implements NfcReader {
  const DemoNfcReader({this.delay = const Duration(seconds: 3)});

  final Duration delay;

  @override
  Future<NfcStatus> status() async => NfcStatus.ready;

  @override
  Future<void> openSettings() async {}

  /// Timers, not an `async*` generator: a generator leaves the wait running
  /// after its listener goes, and a test is told so.
  @override
  Stream<String> tags() {
    Timer? first;
    Timer? second;
    late final StreamController<String> controller;
    controller = StreamController<String>(
      onListen: () {
        first = Timer(delay, () => controller.add(demoNfcStrangerTag));
        second = Timer(delay * 2, () {
          controller.add(demoNfcSpoolTag);
          unawaited(controller.close());
        });
      },
      onCancel: () {
        first?.cancel();
        second?.cancel();
      },
    );
    return controller.stream;
  }
}
