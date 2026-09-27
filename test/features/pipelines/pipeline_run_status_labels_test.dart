import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/features/pipelines/pipeline_run_status_labels.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('pl'));
  });

  group('targetPrinterName', () {
    const fleet = [
      Printer(id: 3, name: 'X1-Carbon'),
      Printer(id: 7, name: 'P1S w piwnicy'),
    ];

    test('names the printer the pipeline targets', () {
      // The picker used to spell this `#3` while the list beside it resolved
      // the name — the same printer read as two things on two screens.
      expect(targetPrinterName(l10n, fleet, 3), 'X1-Carbon');
      expect(targetPrinterName(l10n, fleet, 7), 'P1S w piwnicy');
    });

    test('an id nothing in the fleet matches still names the id', () {
      // Either the list has not landed yet or the printer really is gone;
      // an empty line would read as "runs on nothing" in both cases.
      expect(targetPrinterName(l10n, fleet, 99), contains('99'));
    });

    test('a fleet that has not loaded yet names the id too', () {
      expect(targetPrinterName(l10n, null, 3), contains('3'));
    });

    test('a pipeline with no target printer has nothing to name', () {
      // Its target is a printer class or a fallback, which the caller words
      // itself — a placeholder here would be shown beside that wording.
      expect(targetPrinterName(l10n, fleet, null), isEmpty);
    });
  });
}
