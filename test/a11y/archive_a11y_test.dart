// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:io';

import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/archive.dart';
import 'package:bambuddy_mobile/core/models/current_user.dart';
import 'package:bambuddy_mobile/core/models/archive_media.dart';
import 'package:bambuddy_mobile/data/archive_repository.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:bambuddy_mobile/core/models/no_3mf_warning.dart';
import 'package:bambuddy_mobile/core/models/timelapse.dart';
import 'package:bambuddy_mobile/features/archive/archive_media_sheet.dart'
    show archiveMediaSupportedProvider;
import 'package:bambuddy_mobile/features/archive/archive_filament_edit.dart'
    show filamentGramsMax, filamentGramsText;
import 'package:bambuddy_mobile/features/archive/archive_photos_screen.dart';
import 'package:bambuddy_mobile/features/archive/archive_providers.dart';
import 'package:bambuddy_mobile/features/archive/archive_screen.dart';
import 'package:bambuddy_mobile/features/archive/outcome_sheet.dart';
import 'package:bambuddy_mobile/features/archive/timelapse_editor_screen.dart';
import 'package:bambuddy_mobile/features/archive/timelapse_providers.dart';
import 'package:bambuddy_mobile/features/archive/timelapse_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../helpers.dart';
import 'a11y_harness.dart';
import 'files_a11y_test.dart' show heldDownloadOverride, installTempCache;

/// Rendered contrast and touch targets for the archive: the list (empty, no
/// matches, selection mode, the no-3MF banner in its three causes), the filter
/// sheet, the menu and the dialogs and sheets it opens, the detail sheet of a
/// print in each state the demo seeds, the media and outcome sheets, the photo
/// viewer, the timelapse player and its editor. The harness and the rules are in
/// a11y_harness.dart. The demo has no timelapse on any archive, so the player
/// and the editor run on a fake video platform that shows a demo camera frame
/// where the platform view would be. Not covered: the save dialog a
/// finished media download hands to, and the OS share and save-to-gallery steps
/// of the player (platform pickers). The media sheet's download in flight shares
/// its held-preparation fake with the file manager's test.
///
/// Demo archives by id: 40 Bag dispenser (multi-plate, project, tags, note, 3
/// runs, photo, printer media), 41 Mikrus slot (awaiting a verdict, a link),
/// 42 Xbox controller lid, 43 Dreame bumper support (rejected), 44 Box plate 2
/// (failed), 46 Pet feeder plate 2 (two photos), 48 SAMLA clips (good), 49
/// Handle (failed, nothing measured), 51 Vacuum diffuser (no photo).

const _bag = 'Bag dispenser';
const _mikrus = 'Mikrus slot';
const _xbox = 'Xbox controller lid';
const _dreame = 'Dreame L10s bumper support';
const _boxFailed = 'Box – plate 2';
const _samla = 'IKEA SAMLA box clips';
const _handle = 'Handle';
const _vacuum = 'Vacuum diffuser';

/// The list's card for a print, tapped to open its detail sheet.
Future<void> _openSheetOf(WidgetTester tester, String name) =>
    a11yTap(tester, find.text(name));

/// The detail sheet of [name], then a control in it. The sheet pops itself
/// before opening the next surface, so the second tap is on the new route.
Future<void> _viaSheet(WidgetTester tester, String name, String logId) async {
  await _openSheetOf(tester, name);
  await a11yTap(tester, byLogId(logId));
}

/// A video platform that plays nothing: the player reaches its first frame at
/// once and draws a demo camera frame where the texture would be, so the
/// transport bar is measured over the picture the demo shows.
class _FakeVideoPlatform extends VideoPlayerPlatform {
  static final _frame = File(
    'assets/demo/camera/bag-dispenser-04.webp',
  ).readAsBytesSync();

  final _streams = <int, StreamController<VideoEvent>>{};
  int _next = 0;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final stream = StreamController<VideoEvent>();
    stream.add(
      VideoEvent(
        eventType: VideoEventType.initialized,
        size: const Size(1920, 1080),
        duration: const Duration(seconds: 54),
      ),
    );
    _streams[_next] = stream;
    return _next++;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _streams[playerId]!.stream;

  @override
  Future<void> dispose(int playerId) async {}

  @override
  Future<void> play(int playerId) async {}

  @override
  Future<void> pause(int playerId) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<Duration> getPosition(int playerId) async =>
      const Duration(seconds: 12);

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Future<void> setPreventsDisplaySleepDuringVideoPlayback(
    int playerId,
    bool preventsDisplaySleepDuringVideoPlayback,
  ) async {}

  @override
  Widget buildView(int playerId) => Image.memory(_frame, fit: BoxFit.cover);
}

final _video = _FakeVideoPlatform();

/// [screen] with the fake video platform installed.
Widget _withVideo(Widget screen) {
  VideoPlayerPlatform.instance = _video;
  return screen;
}

/// A fixed archive list that also builds the API client the way the real list
/// does, so the no-3MF banner does not create it in the middle of its own build.
class _FixedArchives extends ArchiveNotifier {
  _FixedArchives(this._rows);

  final List<Archive> _rows;

  @override
  Future<List<Archive>> build() async {
    ref.read(apiClientProvider);
    return _rows;
  }
}

/// An archive repository whose printer search always fails, for the media
/// sheet's error state: the demo answers every search.
class _SearchRefused extends ArchiveRepository {
  _SearchRefused() : super(Dio());

  @override
  Future<ArchivePrinterMedia?> printerMedia(int archiveId) async =>
      throw const ApiException(AppErrorCode.serverUnreachable);
}

void main() {
  installTempCache();

  // --- The list ---

  a11ySurface(
    'archive list',
    home: () => const ArchiveScreen(),
    shows: find.text(_bag),
  );

  a11ySurface(
    'archive list, empty',
    demo: false,
    overrides: [archiveListOverride(const [])],
    home: () => const ArchiveScreen(),
    shows: find.text(pl.archiveEmpty),
  );

  a11ySurface(
    'archive list, search with no matches',
    home: () => const ArchiveScreen(),
    arrange: (tester) async {
      await tester.enterText(find.byType(TextField).first, 'zzzz');
      await a11ySettle(tester, const Duration(seconds: 1));
    },
    shows: find.text(pl.archiveNoMatches),
  );

  a11ySurface(
    'archive list, selection mode',
    home: () => const ArchiveScreen(),
    arrange: (tester) async {
      await tester.longPress(find.text(_bag));
      await tester.tap(find.text(_xbox));
    },
    shows: find.text(pl.archiveSelectedCount(2)),
  );

  // Cards the demo has no rows for: a favorite, a recorded timelapse beside
  // photos on the thumbnail, every verdict mark. (The demo does not serve the
  // favorite toggle, so a tap there cannot reach this state; see the report.)
  final varied = [
    archiveProvider.overrideWith(
      () => _FixedArchives([
        Archive(
          id: 40,
          filename: 'Bag dispenser.gcode.3mf',
          status: 'completed',
          printName: _bag,
          printerId: 1,
          plateId: 2,
          isFavorite: true,
          timelapsePath: 'archive/40/bag.mp4',
          photos: const ['bag-dispenser.jpg', 'second.jpg'],
          userVerdict: PrintVerdict.good,
        ),
        Archive(
          id: 43,
          filename: 'bumper.gcode.3mf',
          status: 'completed',
          printName: _dreame,
          printerId: 1,
          userVerdict: PrintVerdict.reject,
        ),
        Archive(
          id: 41,
          filename: 'mikrus.gcode.3mf',
          status: 'completed',
          printName: _mikrus,
          printerId: 1,
          confirmRequested: true,
        ),
      ]),
    ),
  ];

  a11ySurface(
    'archive list, every card variant',
    overrides: varied,
    home: () => const ArchiveScreen(),
    shows: find.byIcon(Icons.star),
  );

  a11ySurface(
    'archive media sheet, an attached timelapse and photos',
    overrides: varied,
    home: () => const ArchiveScreen(),
    arrange: (tester) => _viaSheet(tester, _bag, 'archive.media'),
    shows: byLogId('archive_media.timelapse'),
  );

  // A card held half-way across shows the red background the swipe reveals.
  a11ySurface(
    'archive list, card swiped for delete',
    home: () => const ArchiveScreen(),
    arrange: (tester) async {
      final swipe = await tester.startGesture(
        tester.getCenter(find.text(_bag)),
      );
      addTearDown(swipe.up);
      await swipe.moveBy(const Offset(-160, 0));
      await tester.pump();
    },
    shows: byLogId('archive.swipe_delete'),
  );

  a11ySurface(
    'archive list, menu',
    home: () => const ArchiveScreen(),
    arrange: (tester) => a11yTap(tester, byLogId('archive.menu')),
    shows: find.text(pl.archivePurgeOlder),
  );

  for (final reason in No3mfReason.values) {
    a11ySurface(
      'archive list, no-3MF banner (${reason.name})',
      overrides: [
        no3mfWarningProvider.overrideWith(
          (ref) async => No3mfWarning(hasFallback: true, reason: reason),
        ),
      ],
      home: () => const ArchiveScreen(),
      shows: byLogId('archive.no3mf_dismiss'),
    );
  }

  // --- Filters ---

  a11ySurface(
    'archive filters',
    home: () => const ArchiveScreen(),
    arrange: (tester) => a11yTap(tester, byLogId('archive.filters')),
    shows: find.text(pl.archiveSortLabel),
  );

  a11ySurface(
    'archive filters, chosen',
    home: () => const ArchiveScreen(),
    arrange: (tester) async {
      await a11yTap(tester, byLogId('archive.filters'));
      await a11yTap(tester, find.text(pl.archiveFilterHideFailed));
      await a11yTap(tester, find.text(pl.archiveSortNameAsc));
      // Two swatches make the any/all segments appear.
      final swatches = find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_ColorSwatch',
      );
      await a11yTap(tester, swatches.at(0));
      await a11yTap(tester, swatches.at(1));
    },
    shows: find.text(pl.archiveColorModeAll),
  );

  // --- Dialogs of the list ---

  a11ySurface(
    'archive purge dialog',
    home: () => const ArchiveScreen(),
    arrange: (tester) async {
      await a11yTap(tester, byLogId('archive.menu'));
      await a11yTap(tester, find.text(pl.archivePurgeOlder));
      await a11ySettle(tester, const Duration(seconds: 1));
    },
    shows: find.text(pl.archivePurgeTitle),
  );

  a11ySurface(
    'archive purge dialog, days menu open',
    home: () => const ArchiveScreen(),
    arrange: (tester) async {
      await a11yTap(tester, byLogId('archive.menu'));
      await a11yTap(tester, find.text(pl.archivePurgeOlder));
      await a11ySettle(tester, const Duration(seconds: 1));
      await a11yTap(tester, find.byType(DropdownMenu<int>));
    },
    shows: find.text(pl.archivePurgeDaysOption(365)),
  );

  a11ySurface(
    'archive purge dialog, nothing that old',
    home: () => const ArchiveScreen(),
    arrange: (tester) async {
      await a11yTap(tester, byLogId('archive.menu'));
      await a11yTap(tester, find.text(pl.archivePurgeOlder));
      await a11ySettle(tester, const Duration(seconds: 1));
      await a11yTap(tester, find.byType(DropdownMenu<int>));
      await a11yTap(tester, find.text(pl.archivePurgeDaysOption(365)).last);
      await a11ySettle(tester, const Duration(seconds: 1));
    },
    shows: find.text(pl.archivePurgeNothing),
  );

  a11ySurface(
    'archive delete dialog',
    home: () => const ArchiveScreen(),
    arrange: (tester) => _viaSheet(tester, _bag, 'archive.delete'),
    shows: find.text(pl.archiveDeletePurgeStats),
  );

  a11ySurface(
    'archive delete dialog, stats choice ticked',
    home: () => const ArchiveScreen(),
    arrange: (tester) async {
      await _viaSheet(tester, _bag, 'archive.delete');
      await a11yTap(tester, byLogId('archive_delete.purge_stats'));
    },
    shows: find.text(pl.archiveDeletePurgeStats),
  );

  a11ySurface(
    'archive bulk delete dialog',
    home: () => const ArchiveScreen(),
    arrange: (tester) async {
      await tester.longPress(find.text(_bag));
      await a11ySettle(tester, const Duration(milliseconds: 500));
      await a11yTap(tester, byLogId('archive.delete_selected'));
    },
    shows: find.text(pl.archiveDeleteSelectedBody),
  );

  a11ySurface(
    'archive project picker',
    home: () => const ArchiveScreen(),
    arrange: (tester) async {
      await tester.longPress(find.text(_bag));
      await a11ySettle(tester, const Duration(milliseconds: 500));
      await a11yTap(tester, byLogId('archive.add_to_project'));
    },
    shows: find.text(pl.projectPickTitle),
  );

  // --- The detail sheet, one print per state it has ---

  for (final (name, why) in [
    (_bag, 'multi-plate, project, tags, note, three runs'),
    (_mikrus, 'awaiting a verdict, with a link'),
    (_xbox, 'plain'),
    (_dreame, 'rejected'),
    (_samla, 'accepted'),
    (_boxFailed, 'failed, partial usage'),
    (_handle, 'failed, nothing measured'),
    (_vacuum, 'no photo'),
  ]) {
    a11ySurface(
      'archive sheet, $name ($why)',
      home: () => const ArchiveScreen(),
      arrange: (tester) => _openSheetOf(tester, name),
      shows: byLogId('sheet.archive_detail'),
    );
  }

  a11ySurface(
    'archive sheet, reprint refused',
    overrides: [
      currentUserOverride(
        const CurrentUser(id: 9, username: 'viewer', isAdmin: false),
      ),
    ],
    home: () => const ArchiveScreen(),
    arrange: (tester) => _openSheetOf(tester, _bag),
    shows: find.text(pl.archiveReprintNoQueue),
  );

  // A disabled slice button explains itself in a tooltip on a tap.
  a11ySurface(
    'archive sheet, why slicing is off',
    home: () => const ArchiveScreen(),
    arrange: (tester) async {
      await _openSheetOf(tester, _xbox);
      await a11yTap(tester, byLogId('archive.slice'));
    },
    shows: find.text(pl.archiveNotSliceable),
  );

  a11ySurface(
    'archive sheet, weight dialog',
    home: () => const ArchiveScreen(),
    arrange: (tester) async {
      await _openSheetOf(tester, _bag);
      await a11yTap(tester, byLogId('archive.filament_edit'));
    },
    shows: byLogId('archive_filament.field'),
  );

  a11ySurface(
    'archive sheet, weight dialog with a refused value',
    home: () => const ArchiveScreen(),
    arrange: (tester) async {
      await _openSheetOf(tester, _bag);
      await a11yTap(tester, byLogId('archive.filament_edit'));
      await tester.enterText(
        find.descendant(
          of: byLogId('archive_filament.field'),
          matching: find.byType(EditableText),
        ),
        '99999999',
      );
      await a11yTap(tester, byLogId('archive_filament.save'));
    },
    shows: find.text(
      pl.archiveFilamentOutOfRange(filamentGramsText(filamentGramsMax)),
    ),
  );

  // --- Media sheet: what the demo's printer holds for each print ---

  for (final (name, what) in [
    (_bag, 'photo, timelapse and camera clips on the printer'),
    (_mikrus, 'a timelapse and a warning about the clips'),
    (_xbox, 'nothing left on the printer'),
  ]) {
    a11ySurface(
      'archive media sheet, $name ($what)',
      home: () => const ArchiveScreen(),
      arrange: (tester) => _viaSheet(tester, name, 'archive.media'),
      shows: byLogId('sheet.archive_media'),
    );
  }

  a11ySurface(
    'archive media sheet, a printer file ticked',
    home: () => const ArchiveScreen(),
    arrange: (tester) async {
      await _viaSheet(tester, _bag, 'archive.media');
      await a11yTap(tester, byLogId('archive_media.file'));
    },
    shows: find.text(pl.archiveMediaDownloadSelected(1)),
  );

  a11ySurface(
    'archive media sheet, download preparing',
    overrides: [heldDownloadOverride],
    home: () => const ArchiveScreen(),
    arrange: (tester) async {
      await _viaSheet(tester, _bag, 'archive.media');
      await a11yTap(tester, byLogId('archive_media.select_all'));
      await a11yTap(tester, byLogId('archive_media.download'));
      await a11ySettle(tester, const Duration(seconds: 1));
    },
    shows: byLogId('archive_media.download_cancel'),
  );

  a11ySurface(
    'archive media sheet, search refused',
    demo: false,
    overrides: [
      archiveListOverride([_archiveFixture()]),
      archiveRepositoryProvider.overrideWithValue(_SearchRefused()),
      archiveMediaSupportedProvider.overrideWithValue(const AsyncData(true)),
    ],
    home: () => const ArchiveScreen(),
    arrange: (tester) => _viaSheet(tester, _fixtureName, 'archive.media'),
    shows: byLogId('archive_media.retry'),
  );

  // --- Outcome sheet ---

  for (final (id, what) in [
    (41, 'awaiting'),
    (43, 'rejected'),
    (48, 'accepted'),
  ]) {
    a11ySurface(
      'outcome sheet, $what',
      home: () => A11yLauncher((context) => showOutcomeSheet(context, id)),
      arrange: a11yOpenLauncher,
      shows: byLogId('sheet.outcome'),
    );
  }

  a11ySurface(
    'outcome sheet, reason step',
    home: () => A11yLauncher((context) => showOutcomeSheet(context, 41)),
    arrange: (tester) async {
      await a11yOpenLauncher(tester);
      await a11yTap(tester, byLogId('outcome.reject'));
    },
    shows: byLogId('outcome.reject_save'),
  );

  a11ySurface(
    'outcome sheet, reason menu open',
    home: () => A11yLauncher((context) => showOutcomeSheet(context, 41)),
    arrange: (tester) async {
      await a11yOpenLauncher(tester);
      await a11yTap(tester, byLogId('outcome.reject'));
      await a11yTap(tester, find.byType(DropdownMenu<String>));
    },
    shows: find.text(pl.outcomeNoReason),
  );

  // --- Photo viewer ---

  a11ySurface(
    'archive photos',
    home: () => const ArchivePhotosScreen(archiveId: 40, title: _bag),
    shows: find.byType(PageView),
  );

  a11ySurface(
    'archive photos, several',
    home: () => const ArchivePhotosScreen(archiveId: 46, title: _bag),
    shows: find.text('1 / 2'),
  );

  a11ySurface(
    'archive photos, none',
    home: () => const ArchivePhotosScreen(archiveId: 44, title: _boxFailed),
    shows: find.text(pl.archivePhotosEmpty),
  );

  // --- Timelapse player ---

  a11ySurface(
    'timelapse player',
    home: () => _withVideo(const TimelapseScreen(archiveId: 40, title: _bag)),
    shows: byLogId('timelapse.play_pause'),
  );

  // No server profile: the player has nothing to open and shows its error view.
  // A player the platform refuses is not driven here: its retry path hangs
  // the test clock (see the report).
  a11ySurface(
    'timelapse player, nothing to open',
    demo: false,
    overrides: [noServerProfileOverride],
    home: () => const TimelapseScreen(archiveId: 40, title: _bag),
    shows: find.text(pl.retry),
  );

  // --- Timelapse editor ---

  final editor = [
    a11yDemoProfileOverride,
    timelapseInfoProvider(40).overrideWith((ref) async => _info),
    timelapseFilmstripProvider(40).overrideWith((ref) async => _filmstrip()),
  ];

  a11ySurface(
    'timelapse editor',
    demo: false,
    overrides: editor,
    home: () => _withVideo(const TimelapseEditorScreen(archiveId: 40)),
    shows: byLogId('timelapse_edit.save'),
  );

  a11ySurface(
    'timelapse editor, no preview',
    demo: false,
    overrides: [noServerProfileOverride, ...editor.skip(1)],
    home: () => const TimelapseEditorScreen(archiveId: 40),
    shows: byLogId('timelapse_edit.save'),
  );

  a11ySurface(
    'timelapse editor, frames still rendering',
    demo: false,
    overrides: [
      a11yDemoProfileOverride,
      timelapseInfoProvider(40).overrideWith((ref) async => _info),
      timelapseFilmstripProvider(
        40,
      ).overrideWith((ref) => Completer<TimelapseFilmstrip>().future),
    ],
    home: () => _withVideo(const TimelapseEditorScreen(archiveId: 40)),
    shows: byLogId('timelapse_edit.save'),
  );

  a11ySurface(
    'timelapse editor, info refused',
    demo: false,
    overrides: [
      noServerProfileOverride,
      timelapseInfoProvider(40).overrideWith(
        (ref) async => throw const ApiException(AppErrorCode.badResponse),
      ),
      timelapseFilmstripProvider(40).overrideWith((ref) async => _filmstrip()),
    ],
    home: () => const TimelapseEditorScreen(archiveId: 40),
    shows: find.text(pl.retry),
  );

  a11ySurface(
    'timelapse editor, save confirmation',
    demo: false,
    overrides: editor,
    home: () => _withVideo(const TimelapseEditorScreen(archiveId: 40)),
    arrange: (tester) => a11yTap(tester, byLogId('timelapse_edit.save')),
    shows: byLogId('timelapse_edit_save.confirm'),
  );
}

const _info = TimelapseInfo(
  duration: 54,
  width: 1920,
  height: 1080,
  fps: 30,
  codec: 'h264',
  fileSize: 12345,
  hasAudio: false,
);

/// Fourteen frames the way the server renders a filmstrip, here the demo's
/// camera frames so the strip is measured over the picture it shows.
TimelapseFilmstrip _filmstrip() {
  final frames = [
    for (var i = 0; i < 12; i++)
      File(
        'assets/demo/camera/bag-dispenser-${i.toString().padLeft(2, '0')}.webp',
      ).readAsBytesSync(),
  ];
  return TimelapseFilmstrip(
    frames: frames,
    timestamps: [for (var i = 0; i < 12; i++) i * 4.5],
  );
}

const _fixtureName = 'Test print';

/// A print on a printer the media search cannot reach, for the sheet's error
/// state: the demo answers every search.
Archive _archiveFixture() => Archive(
  id: 500,
  filename: 'print.gcode.3mf',
  status: 'completed',
  printName: _fixtureName,
  printerId: 1,
  photos: const ['finish.jpg'],
);
