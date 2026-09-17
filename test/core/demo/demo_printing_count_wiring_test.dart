import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Two isolates on the phone run their own copy of the demo — the app and the
/// foreground service — and each has to be told how many printers are printing
/// before it answers a single status.
///
/// The provider that owns the setting cannot do it. Nothing watches it until
/// the settings screen is opened, so on a cold start the dashboard showed one
/// printing printer however the slider had been left, and the notification
/// disagreed with the dashboard. Each entry point makes the read itself.
///
/// The watch is deliberately not on this list: it is a separate device with its
/// own preferences, the slider writes to the phone's, and nothing syncs the two.
/// A read there would look like wiring and be dead code.
///
/// Matched on the two names rather than on an expression: `dart format` splits
/// the call across lines, and a scan written to a line shape breaks on that
/// without anything being wrong. Comments are stripped first, so a mention in
/// prose cannot stand in for the call.
void main() {
  /// The file with its `//` comments and doc comments removed.
  String codeOf(String path) => File(path)
      .readAsLinesSync()
      .where((line) => !line.trimLeft().startsWith('//'))
      .join('\n');

  test('every entry point applies the saved demo count at start-up', () {
    const entryPoints = [
      'lib/main.dart',
      'lib/core/notifications/print_monitor_task_handler.dart',
    ];

    for (final path in entryPoints) {
      final code = codeOf(path);
      expect(
        code,
        contains('DemoBackend.printingPrinters'),
        reason: '$path does not tell its demo how many printers print',
      );
      expect(
        code,
        contains('loadDemoPrintingCount'),
        reason: '$path does not read the saved count',
      );
    }
  });

  test('the watch is left out, and stays left out by accident of nothing', () {
    // If a sync layer ever carries the setting to the watch, this is the test
    // that should fail and be rewritten — not a comment nobody reads.
    expect(
      codeOf('lib/wear/main_wear.dart'),
      isNot(contains('loadDemoPrintingCount')),
      reason:
          'the watch has its own preferences; the phone slider never '
          'reaches them, so a read there would be dead code',
    );
  });
}
