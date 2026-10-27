import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:app_report_ui/app_report_ui.dart';
import 'package:bambuddy_mobile/core/diagnostics/report_config.dart';
import 'package:bambuddy_mobile/core/models/announcement.dart';
import 'package:bambuddy_mobile/features/about/about_screen.dart';
import 'package:bambuddy_mobile/features/announcements/announcements_providers.dart';
import 'package:bambuddy_mobile/features/announcements/announcements_screen.dart';
import 'package:bambuddy_mobile/features/bug_report/report_wiring.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../helpers.dart';
import 'a11y_harness.dart';

/// Rendered contrast and touch targets for About, the announcements inbox and
/// the bug report (`lib/features/bug_report` is only the wiring; the screens are
/// `app_report_ui`'s, drawn here in this app's theme and consent lines).
/// About: the screen and the licence page behind its last row. Announcements:
/// the demo inbox, an opened item with its link, the folded-away "earlier" part,
/// all three levels, the empty inbox and a failed load. Bug report: the three
/// kinds, the recording view and the review of a finished log. Not covered: the
/// recording bar (`RecordingBannerScaffold` wraps the whole app, so it is
/// measured on top of no screen of this slice), the card offering a log salvaged
/// from a crash and the relay's send states (queued, sending, failed), which
/// need a session left on disk and a scripted sender this app does not own.
void main() {
  setUpAll(
    () => PackageInfo.setMockInitialValues(
      appName: 'bambuddy',
      packageName: 'page.codeberg.morganmlgman.bambuddy_mobile',
      version: '0.17.0',
      buildNumber: '2029000',
      buildSignature: '',
    ),
  );

  _about();
  _announcements();
  _bugReport();
}

void _about() {
  a11ySurface(
    'about',
    home: () => const AboutScreen(),
    shows: find.text(pl.aboutLicenseHeader),
  );

  a11ySurface(
    'about, licence page',
    home: () => const AboutScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('about.licenses'));
      await settle(tester);
    },
    shows: find.text(pl.bgServiceTitle),
  );
}

void _announcements() {
  a11ySurface(
    'announcements',
    home: () => const AnnouncementsScreen(),
    shows: find.byType(AnnouncementTile),
  );

  a11ySurface(
    'announcements, item opened',
    home: () => const AnnouncementsScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('announcements.item').first);
      await settle(tester);
    },
    shows: find.text(pl.announcementsReadMore),
  );

  a11ySurface(
    'announcements, earlier opened',
    home: () => const AnnouncementsScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('announcements.earlier'));
      await settle(tester);
    },
    shows: find.text(pl.announcementLevelInfo),
  );

  // Critical is the one level the demo inbox never carries.
  a11ySurface(
    'announcements, every level',
    demo: false,
    overrides: [
      noServerProfileOverride,
      announcementsProvider.overrideWith(
        () => _Inbox(
          AnnouncementFeed(
            visible: true,
            items: [
              for (final level in AnnouncementLevel.values)
                _announcement(level.name, level),
            ],
          ),
        ),
      ),
    ],
    home: () => const AnnouncementsScreen(),
    shows: find.text(pl.announcementLevelCritical),
  );

  a11ySurface(
    'announcements, empty inbox',
    demo: false,
    overrides: [
      noServerProfileOverride,
      announcementsProvider.overrideWith(
        () => _Inbox(const AnnouncementFeed(visible: true)),
      ),
    ],
    home: () => const AnnouncementsScreen(),
    shows: find.text(pl.announcementsEmpty),
  );

  a11ySurface(
    'announcements, load failed',
    demo: false,
    overrides: [
      noServerProfileOverride,
      announcementsProvider.overrideWith(() => _Inbox(null)),
    ],
    home: () => const AnnouncementsScreen(),
    shows: find.text(pl.retry),
  );
}

Announcement _announcement(String id, AnnouncementLevel level) => Announcement(
  id: id,
  level: level,
  texts: {
    'en': AnnouncementText(title: 'A $id message', body: 'What it says.'),
  },
  publishedAt: DateTime(2026, 10, 1),
);

/// The inbox standing still on [_feed], or failing when it is null.
class _Inbox extends AnnouncementsNotifier {
  _Inbox(this._feed);

  final AnnouncementFeed? _feed;

  @override
  Future<AnnouncementFeed> build() async =>
      _feed ?? (throw StateError('inbox unavailable'));
}

final _rl = lookupReportLocalizations(const Locale('pl'));

void _bugReport() {
  a11ySurface(
    'bug report',
    demo: false,
    overrides: _reportOverrides(),
    home: () => const BugReportScreen(),
    shows: find.text(pl.bugReportLogService),
  );

  for (final (name, kind) in [
    ('change request', _rl.bugReportKindChange),
    ('feature request', _rl.bugReportKindFeature),
  ]) {
    a11ySurface(
      'bug report, $name',
      demo: false,
      overrides: _reportOverrides(),
      home: () => const BugReportScreen(),
      arrange: (tester) async {
        await tester.tap(find.text(kind));
        await settle(tester);
      },
      shows: find.text(pl.bugReportRequestNoData),
    );
  }

  a11ySurface(
    'bug report, recording',
    demo: false,
    // A fixed state: a real recording holds a semantics handle until it stops,
    // which the harness's own end-of-test check would report as a leak.
    overrides: [
      ..._reportOverrides(),
      bugReportProvider.overrideWith(_Recording.new),
    ],
    home: () => const BugReportScreen(),
    shows: find.text(_rl.bugReportMark),
  );

  a11ySurface(
    'bug report, review',
    demo: false,
    overrides: _reportOverrides(),
    home: () => const BugReportScreen(),
    arrange: (tester) async {
      final controller = _controller(tester);
      await controller.start();
      controller.mark();
      await controller.stop();
      await settle(tester);
    },
    shows: find.text(_rl.bugReportReviewHeader),
  );
}

class _Recording extends BugReportController {
  @override
  BugReportState build() => BugReportState.recording(DateTime(2026, 10, 26));
}

BugReportController _controller(WidgetTester tester) =>
    ProviderScope.containerOf(
      tester.element(find.byType(BugReportScreen)),
    ).read(bugReportProvider.notifier);

/// The app's own report wiring (consent lines included) over a recorder that
/// writes no files and a fixed set of session facts.
List<Override> _reportOverrides() => [
  noServerProfileOverride,
  diagnosticRecorderProvider.overrideWith(
    (ref) => DiagnosticRecorder(
      sessions: ref.watch(settingsRepositoryProvider).diagnosticsSessions,
      redactor: bambuddyRedactor,
      sessionDuration: recordingLimit,
      sessionBytes: recordingSizeLimit,
      loadFacts: () async => const SessionFacts(
        app: '0.17.0+2029000',
        extra: {'flavor': 'mobile'},
      ),
      resolveDirectory: () async => null,
    ),
  ),
  reportBindingsOverride,
];
