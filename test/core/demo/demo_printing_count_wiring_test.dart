import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Three isolates run their own copy of the demo — the phone app, the watch app
/// and the foreground service — and each has to be told how many printers are
/// printing before it answers a single status.
///
/// The provider that owns the setting cannot do it. Nothing watches it until
/// the settings screen is opened, so on a cold start the dashboard showed one
/// printing printer however the slider had been left, and the notification
/// disagreed with the dashboard. Each entry point makes the read itself.
///
/// Matched on the two names rather than on an expression: `dart format` splits
/// the call across lines, and a scan written to a line shape breaks on that
/// without anything being wrong.
void main() {
  test('every entry point applies the saved demo count at start-up', () {
    const entryPoints = [
      'lib/main.dart',
      'lib/wear/main_wear.dart',
      'lib/core/notifications/print_monitor_task_handler.dart',
    ];

    for (final path in entryPoints) {
      final source = File(path).readAsStringSync();
      expect(
        source,
        contains('DemoBackend.printingPrinters'),
        reason: '$path does not tell its demo how many printers print',
      );
      expect(
        source,
        contains('loadDemoPrintingCount'),
        reason: '$path does not read the saved count',
      );
    }
  });
}
