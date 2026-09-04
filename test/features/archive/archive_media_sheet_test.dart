import 'package:bambuddy_mobile/core/format/datetime_format.dart';
import 'package:bambuddy_mobile/core/models/archive.dart';
import 'package:bambuddy_mobile/data/archive_repository.dart';
import 'package:bambuddy_mobile/features/archive/archive_media_sheet.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'dart:ui' show CheckedState;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../../helpers.dart';

/// The sheet groups a print's media by where it actually is, because what can
/// be done with it follows from that: the server's copies open a viewer, the
/// printer's are ticked and downloaded.

const _media = '/api/v1/archives/1/printer-media';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late int timelapseTaps;
  late int photoTaps;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://s.local:8000'));
    adapter = DioAdapter(dio: dio);
    timelapseTaps = 0;
    photoTaps = 0;
  });

  Archive archive({
    int? printerId = 2,
    String? timelapsePath,
    List<String> photos = const [],
  }) =>
      Archive(
        id: 1,
        filename: 'benchy.gcode.3mf',
        status: 'completed',
        printName: 'Benchy',
        printerId: printerId,
        timelapsePath: timelapsePath,
        photos: photos,
      );

  /// Opens the sheet over a bare screen and waits for the search to answer.
  Future<AppLocalizations> open(
    WidgetTester tester,
    Archive item, {
    bool searchable = true,
    TextScaler scaler = TextScaler.noScaling,
  }) async {
    late BuildContext sheetContext;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        noServerProfileOverride,
        archiveRepositoryProvider.overrideWithValue(ArchiveRepository(dio)),
        archiveMediaSupportedProvider.overrideWith((ref) async => searchable),
      ],
      child: plApp(
        Builder(builder: (context) {
          sheetContext = context;
          return const SizedBox.shrink();
        }),
        // Wraps the navigator, so the sheet's own route sees it too.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: scaler),
          child: child!,
        ),
      ),
    ));
    openArchiveMediaSheet(
      sheetContext,
      item,
      onTimelapse: () => timelapseTaps++,
      onPhotos: () => photoTaps++,
    );
    await tester.pumpAndSettle();
    return AppLocalizations.of(sheetContext);
  }

  void replyWith(Map<String, dynamic> body) =>
      adapter.onGet(_media, (s) => s.reply(200, body));

  testWidgets('the two places are named, and each row does its own thing',
      (tester) async {
    replyWith(const {
      'archive_id': 1,
      'printer_id': 2,
      'local_timelapse': {'name': 'benchy.mp4', 'size': 4096},
      'remote_files': [
        {
          'name': 'ipcam_1.mp4',
          'path': '/ipcam/ipcam_1.mp4',
          'size': 10,
          'kind': 'ipcam',
        },
      ],
    });

    final l10n = await open(
      tester,
      archive(timelapsePath: 'archive/1/benchy.mp4', photos: const ['a.jpg']),
    );

    expect(find.text(l10n.archiveMediaOnServer), findsOneWidget);
    expect(find.text(l10n.archiveMediaOnPrinter(1)), findsOneWidget);

    // The photos row carries its own count, the way the timelapse row carries
    // its size — a bare digit read as part of the file name beside it.
    expect(find.text(l10n.archiveMediaPhotoCount(1)), findsOneWidget);

    // The server's copies open their viewer rather than downloading here.
    await tester.tap(find.text('benchy.mp4'));
    await tester.tap(find.text(l10n.archivePhotosTitle));
    await tester.pump();
    expect(timelapseTaps, 1);
    expect(photoTaps, 1);

    // The printer's file is a selection, and it was the only candidate.
    expect(find.text(l10n.archiveMediaDownloadSelected(1)), findsOneWidget);
  });

  testWidgets('the timelapse row is named and sized before it is tapped',
      (tester) async {
    replyWith(const {
      'archive_id': 1,
      'printer_id': 2,
      'local_timelapse': {'name': 'benchy.mp4', 'size': 4096},
      'remote_files': <Object>[],
    });

    final l10n =
        await open(tester, archive(timelapsePath: 'archive/1/benchy.mp4'));

    expect(find.text('benchy.mp4'), findsOneWidget);
    expect(
      find.text('${l10n.archiveMediaKindTimelapse} · 4.0 KB'),
      findsOneWidget,
    );
  });

  testWidgets('a pickable row reads as one item that says whether it is ticked',
      (tester) async {
    replyWith(const {
      'archive_id': 1,
      'printer_id': 2,
      'remote_files': [
        {
          'name': 'ipcam_1.mp4',
          'path': '/ipcam/ipcam_1.mp4',
          'size': 10,
          'kind': 'ipcam',
        },
      ],
    });

    await open(tester, archive());
    final handle = tester.ensureSemantics();

    // Read through the row's own text: after the merge it has no node of its
    // own, so what comes back is the row — name, size and state together,
    // rather than a bare tick to swipe past first.
    SemanticsData row() =>
        tester.getSemantics(find.text('ipcam_1.mp4')).getSemanticsData();

    // The lone candidate is ticked already, and the row is what reports it.
    expect(row().flagsCollection.isChecked, CheckedState.isTrue);
    expect(row().label, contains('ipcam_1.mp4'));

    handle.dispose();
  });

  testWidgets('the sheet has headings to jump between', (tester) async {
    // A sheet has no app bar, so nothing marks its title as a heading unless it
    // says so — and the two section names are the whole point of the layout.
    replyWith(const {'archive_id': 1, 'printer_id': 2, 'remote_files': <Object>[]});

    final l10n =
        await open(tester, archive(timelapsePath: 'archive/1/benchy.mp4'));
    final handle = tester.ensureSemantics();

    bool isHeader(String text) => tester
        .getSemantics(find.text(text))
        .getSemanticsData()
        .flagsCollection.isHeader;

    expect(isHeader(l10n.archiveMediaAction), isTrue);
    expect(isHeader(l10n.archiveMediaOnServer), isTrue);
    expect(isHeader(l10n.archiveMediaOnPrinter(0)), isTrue);

    handle.dispose();
  });

  testWidgets('two chunks stay tellable apart when their names cannot be',
      (tester) async {
    // A printer's file name has no spaces, so the line breaker treats it as one
    // unbreakable token: it never wraps, at any maxLines, and on a narrow
    // screen at the system's larger text sizes both of these ellipsise to the
    // same `ipcam_20260903_08…`. The timestamp they differ by is at the end —
    // the half that goes. So the row says the time itself.
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    replyWith(const {
      'archive_id': 1,
      'printer_id': 2,
      'remote_files': [
        {
          'name': 'ipcam_20260903_081500.mp4',
          'path': '/ipcam/ipcam_20260903_081500.mp4',
          'size': 6291456,
          'kind': 'ipcam',
          'mtime': '2026-09-03T08:15:00',
        },
        {
          'name': 'ipcam_20260903_085551.mp4',
          'path': '/ipcam/ipcam_20260903_085551.mp4',
          'size': 6291456,
          'kind': 'ipcam',
          'mtime': '2026-09-03T08:55:51',
        },
      ],
    });

    await open(tester, archive(), scaler: const TextScaler.linear(2));

    // The names do run out of room — that is the premise, not a failure.
    expect(
      tester
          .renderObject<RenderParagraph>(
              find.text('ipcam_20260903_085551.mp4'))
          .didExceedMaxLines,
      isTrue,
    );

    // The subtitles are what the reader picks between, and they differ.
    final times = DateTimeFormats.of(
      tester.element(find.text('ipcam_20260903_085551.mp4')),
    );
    final early = DateTime.utc(2026, 9, 3, 8, 15).toLocal();
    final late = DateTime.utc(2026, 9, 3, 8, 55, 51).toLocal();
    expect(find.textContaining(times.time(early)), findsOneWidget);
    expect(find.textContaining(times.time(late)), findsOneWidget);

    // And the header above them survives the same text size: the button beside
    // it is wider than the whole row there, so it takes a line of its own
    // rather than running off the edge.
    expect(tester.takeException(), isNull);
  });

  testWidgets('a listing with no timestamp says the rest without inventing one',
      (tester) async {
    replyWith(const {
      'archive_id': 1,
      'printer_id': 2,
      'remote_files': [
        {
          'name': 'ipcam_1.mp4',
          'path': '/ipcam/ipcam_1.mp4',
          'size': 6291456,
          'kind': 'ipcam',
        },
      ],
    });

    final l10n = await open(tester, archive());

    expect(
      find.text('${l10n.archiveMediaKindIpcam} · 6.0 MB'),
      findsOneWidget,
    );
  });

  testWidgets('several candidates start unticked', (tester) async {
    replyWith(const {
      'archive_id': 1,
      'printer_id': 2,
      'remote_files': [
        {
          'name': 'ipcam_1.mp4',
          'path': '/ipcam/ipcam_1.mp4',
          'size': 10,
          'kind': 'ipcam',
        },
        {
          'name': 'ipcam_2.mp4',
          'path': '/ipcam/ipcam_2.mp4',
          'size': 10,
          'kind': 'ipcam',
        },
      ],
    });

    final l10n = await open(tester, archive());

    expect(find.text(l10n.archiveMediaDownloadSelected(0)), findsOneWidget);

    await tester.tap(find.text('ipcam_2.mp4'));
    await tester.pump();
    expect(find.text(l10n.archiveMediaDownloadSelected(1)), findsOneWidget);

    await tester.tap(find.text(l10n.pfmSelectAll));
    await tester.pump();
    expect(find.text(l10n.archiveMediaDownloadSelected(2)), findsOneWidget);
  });

  testWidgets('a refused file listing is explained, not swallowed',
      (tester) async {
    // The half the server could give still shows: an API key without printer-
    // file permission reads archives fine, and the attached copy is the
    // archive's own.
    replyWith(const {
      'archive_id': 1,
      'printer_id': 2,
      'local_timelapse': {'name': 'benchy.mp4', 'size': 4096},
      'remote_files': <Object>[],
      'warnings': ['printer_files_forbidden'],
    });

    final l10n =
        await open(tester, archive(timelapsePath: 'archive/1/benchy.mp4'));

    expect(find.text('benchy.mp4'), findsOneWidget);
    expect(find.text(l10n.archiveMediaNoFilePermission), findsOneWidget);
    expect(find.text(l10n.archiveMediaNothingOnPrinter), findsOneWidget);
  });

  testWidgets('a search that broke is not a search that found nothing',
      (tester) async {
    adapter.onGet(_media, (s) => s.reply(500, {'detail': 'boom'}));

    final l10n = await open(tester, archive());

    expect(find.text(l10n.archiveMediaNothingOnPrinter), findsNothing);
  });

  testWidgets('a search that broke can be tried again without leaving',
      (tester) async {
    // Five FTP listings fail for reasons that pass. Dismissing the sheet and
    // finding the button again is not a retry the user should have to perform.
    adapter.onGet(_media, (s) => s.reply(500, {'detail': 'boom'}));

    final l10n = await open(tester, archive());

    // A fresh adapter rather than a counter inside the handler: http_mock_adapter
    // runs the handler once, when the route is declared, so a closure that
    // counts calls answers the same thing every time.
    adapter = DioAdapter(dio: dio);
    replyWith(const {
      'archive_id': 1,
      'printer_id': 2,
      'remote_files': [
        {
          'name': 'ipcam_1.mp4',
          'path': '/ipcam/ipcam_1.mp4',
          'size': 10,
          'kind': 'ipcam',
        },
      ],
    });

    await tester.tap(find.text(l10n.retry));
    await tester.pumpAndSettle();

    expect(find.text('ipcam_1.mp4'), findsOneWidget);
  });

  testWidgets('an older server leaves the printer section out altogether',
      (tester) async {
    // The route is not there, so nothing is asked for. The sheet is still the
    // way to the timelapse and the photos — it simply has nothing to look for.
    final l10n = await open(
      tester,
      archive(timelapsePath: 'archive/1/benchy.mp4'),
      searchable: false,
    );

    expect(find.text(l10n.archiveMediaOnServer), findsOneWidget);
    expect(find.text(l10n.archiveMediaOnPrinter(0)), findsNothing);
    expect(find.text(l10n.archiveMediaNothingOnPrinter), findsNothing);
  });

  testWidgets('a print with no printer is never searched for one',
      (tester) async {
    // No route to call, so nothing is asked: the printer section would have
    // nowhere to look even on a server that has the search.
    final l10n = await open(
      tester,
      archive(printerId: null, timelapsePath: 'archive/1/benchy.mp4'),
    );

    expect(find.text(l10n.archiveMediaOnPrinter(0)), findsNothing);
    expect(find.text('benchy.mp4'), findsOneWidget);
  });
}
