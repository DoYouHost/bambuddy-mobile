import 'package:app_report_ui/app_report_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../router.dart';

/// Hands the shared report screens this app's recorder, sender and consent
/// lines. Goes into every `ProviderScope` that mounts the app or its router.
final Override reportBindingsOverride = reportBindingsProvider.overrideWith(
  (ref) => ReportBindings(
    recorder: ref.watch(diagnosticRecorderProvider),
    sender: ref.watch(reportSenderProvider),
    navigatorKey: rootNavigatorKey,
    // Without a server profile the dashboard would bounce off the router's
    // redirect, so a pre-setup recording goes back to setup.
    homeLocation: () =>
        ref.read(serverProfileProvider) == null ? '/setup' : '/',
    logFilePrefix: 'bambuddy',
    consent: (context) {
      final l10n = AppLocalizations.of(context);
      return (
        recorded: [
          l10n.bugReportLogScreens,
          l10n.bugReportLogRequests,
          // The one nobody expects to be in there.
          l10n.bugReportLogService,
          l10n.bugReportLogErrors,
          l10n.bugReportLogSetup,
        ],
        neverRecorded: [
          l10n.bugReportLogNoKey,
          l10n.bugReportLogNoTyping,
          l10n.bugReportLogNoAddress,
          l10n.bugReportLogNoData,
        ],
        requestExcludes: l10n.bugReportRequestNoData,
      );
    },
  ),
);
