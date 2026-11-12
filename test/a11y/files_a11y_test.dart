import 'dart:async';
import 'dart:io';

import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/cost_center.dart';
import 'package:bambuddy_mobile/core/models/library_file.dart';
import 'package:bambuddy_mobile/core/models/library_file_detail.dart';
import 'package:bambuddy_mobile/core/models/library_folder.dart';
import 'package:bambuddy_mobile/core/models/library_tag.dart';
import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_download_job.dart';
import 'package:bambuddy_mobile/core/models/printer_file.dart';
import 'package:bambuddy_mobile/core/models/trash_file.dart';
import 'package:bambuddy_mobile/data/printer_files_repository.dart';
import 'package:bambuddy_mobile/features/files/file_details_screen.dart';
import 'package:bambuddy_mobile/features/files/file_manager_providers.dart';
import 'package:bambuddy_mobile/features/files/file_manager_screen.dart';
import 'package:bambuddy_mobile/features/files/printer_file_manager_screen.dart';
import 'package:bambuddy_mobile/features/files/queue_cost_center_sheet.dart';
import 'package:bambuddy_mobile/features/files/queue_target_sheet.dart';
import 'package:bambuddy_mobile/features/files/trash_screen.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dash_kit/dash_kit.dart' show DashLoading;
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../helpers.dart';
import 'a11y_harness.dart';

/// Rendered contrast and touch targets for the file manager: the library (the
/// demo's, and a hand-built listing with every row variant: tags, variants,
/// photos, an external mount, folders the user may not touch), selection mode,
/// every sheet and menu it opens (sort, create, file actions in each shape,
/// move, tags in all four forms, cost center and printer for a bulk add), the
/// confirmations and name prompts, the trash, the file details and photo
/// viewer, and the printer's own file manager with its download in flight. The
/// harness and the rules are in a11y_harness.dart. Not covered: the file
/// photos, which the demo has no pictures for (the tiles show the picture
/// placeholder), the system pickers behind Upload and Add photo, and the
/// save dialog a finished download hands to. Exported for the archive file:
/// [HeldDownloadRepo] and [installTempCache], which the media sheet's download
/// shares with the printer's file manager.
///
/// Demo library: folders 'Server rack' (1: plate 12, 13, 14) and 'Household'
/// (2: Bag dispenser, Gridfinity bin); at the root the sources 'Crimper 24 mm'
/// (3MF), 'Mop station' (3MF), 'Rack rails' (STL) and 'Server rack – plate 22'
/// (STEP, no thumbnail).

/// Points the app's temporary directory at a fresh folder for each test, which
/// a download needs for its part-file; no platform channel answers in a test.
void installTempCache() {
  late Directory cache;
  setUp(() async {
    cache = await Directory.systemTemp.createTemp('a11y-cache');
    PathProviderPlatform.instance = TempDirProvider(cache.path);
  });
  tearDown(() async {
    if (cache.existsSync()) await cache.delete(recursive: true);
  });
}

/// The demo's printer storage with one change: a prepared download that never
/// gets past `preparing`, so the progress row and its Cancel button stay on
/// screen for the measurement. The poll waits on a future nobody completes, so
/// no timer outlives the test.
class HeldDownloadRepo extends PrinterFilesRepository {
  HeldDownloadRepo(super.dio);

  @override
  Future<bool> supportsDownloadJobs() async => true;

  @override
  Future<PrinterDownloadJob?> startDownloadJob(
    int printerId, {
    required List<String> paths,
    required Map<String, int> sizes,
    required String filename,
    bool asZip = true,
  }) async => PrinterDownloadJob(
    jobId: 'held',
    printerId: printerId,
    state: PrinterDownloadJobState.preparing,
    requested: paths.length,
    successful: paths.length > 1 ? 1 : 0,
    failed: 0,
  );

  @override
  Future<PrinterDownloadJob?> downloadJob(int printerId, String jobId) =>
      Completer<PrinterDownloadJob?>().future;

  @override
  Future<void> cancelDownloadJob(int printerId, String jobId) async {}
}

/// [HeldDownloadRepo] over the demo's dio.
final heldDownloadOverride = printerFilesRepositoryProvider.overrideWith(
  (ref) => HeldDownloadRepo(ref.watch(apiClientProvider).dio),
);

/// A printer file manager listing [listing] and nothing else, for the states
/// the demo's printers never reach.
class _FixedPrinterFiles extends PrinterFilesRepository {
  _FixedPrinterFiles({this.listing = const PrinterFileListing(), this.fails})
    : super(Dio());

  final PrinterFileListing listing;
  final AppApiException? fails;

  @override
  Future<PrinterFileListing> listFiles(int printerId, String path) async {
    final failure = fails;
    if (failure != null) throw failure;
    return listing;
  }

  @override
  Future<PrinterStorage> fetchStorage(int printerId) async =>
      const PrinterStorage(usedBytes: 4294967296);
}

/// A library listing the test decides, in place of the demo's.
class _Listing extends FileManagerNotifier {
  _Listing(this._state);

  final FileManagerState _state;

  @override
  Future<FileManagerState> build() async => _state;

  @override
  Future<void> refresh() async {}
}

/// Every row variant the listing has. Ids 1 to 9 are the demo's own library
/// files, so each row that claims a thumbnail has a demo picture.
final _kitchenSink = FileManagerState(
  allFolders: const [
    LibraryFolder(id: 1, name: 'Server rack', fileCount: 3),
    LibraryFolder(
      id: 2,
      name: 'Mounted share',
      isExternal: true,
      externalReadonly: true,
      fileCount: 12,
    ),
    LibraryFolder(
      id: 3,
      name: 'Somebody else\'s',
      canWrite: false,
      canRename: false,
      canDelete: false,
      fileCount: 1,
    ),
  ],
  files: [
    LibraryFile(
      id: 1,
      filename: 'Server rack – plate 12.gcode.3mf',
      fileType: 'gcode.3mf',
      fileSize: 2108509,
      printCount: 3,
      thumbnailPath: 'library/demo/rack-plate-12.png',
      createdByUsername: 'demo',
      slicedForModel: 'X1C',
      variantGroupId: 1,
      variantCount: 2,
      photoCount: 3,
      externalUrl: 'https://www.printables.com/',
      hasNotes: true,
      tags: const [
        LibraryTag(id: 1, name: 'rack'),
        LibraryTag(id: 2, name: 'PETG'),
        LibraryTag(id: 3, name: 'for the workshop'),
        LibraryTag(id: 4, name: 'gift'),
        LibraryTag(id: 5, name: 'needs supports'),
      ],
    ),
    const LibraryFile(
      id: 4,
      filename: 'Bag dispenser.gcode.3mf',
      fileType: 'gcode.3mf',
      fileSize: 4318208,
      printCount: 2,
      thumbnailPath: 'library/demo/bag-dispenser.png',
      isExternal: true,
      slicedForModel: 'P1S',
    ),
    const LibraryFile(
      id: 6,
      filename:
          'A very long model name that has to wrap onto a second line.3mf',
      fileType: '3mf',
      fileSize: 634212,
      printCount: 0,
      thumbnailPath: 'library/demo/crimper.png',
    ),
    const LibraryFile(
      id: 9,
      filename: 'Server rack – plate 22.step',
      fileType: 'step',
      fileSize: 412160,
      printCount: 0,
    ),
  ],
);

final _tags = [
  const LibraryTag(id: 1, name: 'rack', fileCount: 4),
  const LibraryTag(id: 2, name: 'PETG', fileCount: 2),
  const LibraryTag(id: 3, name: 'for the workshop', fileCount: 1),
  const LibraryTag(id: 4, name: 'gift'),
];

/// A server with the tag routes: the gate open and a catalog to show.
final _withTags = [
  libraryTagsSupportedProvider.overrideWithValue(const AsyncData(true)),
  libraryTagsProvider.overrideWith((ref) async => _tags),
];

final _sinkListing = [
  fileManagerProvider.overrideWith(() => _Listing(_kitchenSink)),
];

const _crimper = 'Crimper 24 mm';
const _mop = 'Mop station';
const _rails = 'Rack rails';
const _step = 'Server rack – plate 22';
const _plate12 = 'Server rack – plate 12';
const _plate13 = 'Server rack – plate 13';

/// The hand-built listing's rows carry no print name, so they show the file name.
const _sinkPlate12 = 'Server rack – plate 12.gcode.3mf';
const _longName =
    'A very long model name that has to wrap onto a second line.3mf';

void main() {
  installTempCache();

  // --- The library, on the demo's data ---

  a11ySurface(
    'library',
    home: () => const FileManagerScreen(),
    shows: find.text(_crimper),
  );

  a11ySurface(
    'library, inside a folder',
    home: () => const FileManagerScreen(folderId: 1),
    shows: find.text(_plate12),
  );

  a11ySurface(
    'library, selection mode',
    home: () => const FileManagerScreen(),
    arrange: (tester) async {
      await a11yLongPress(tester, find.text(_crimper));
      await a11yTap(tester, find.text(_mop));
    },
    shows: find.text(pl.fmSelectedCount(2)),
  );

  a11ySurface(
    'library, file type menu',
    home: () => const FileManagerScreen(),
    arrange: (tester) => a11yTap(tester, byLogId('files.filter_type')),
    shows: find.text(pl.fmAllTypes),
  );

  a11ySurface(
    'library, sort sheet',
    home: () => const FileManagerScreen(),
    arrange: (tester) => a11yTap(tester, byLogId('files.sort')),
    shows: find.text(pl.fmSortNameAZ),
  );

  a11ySurface(
    'library, create sheet',
    home: () => const FileManagerScreen(),
    arrange: (tester) => a11yTap(tester, byLogId('files.create')),
    shows: find.text(pl.fmNewFolder),
  );

  a11ySurface(
    'library, new folder prompt',
    home: () => const FileManagerScreen(),
    arrange: (tester) async {
      await a11yTap(tester, byLogId('files.create'));
      await a11yTap(tester, byLogId('files.new_folder'));
    },
    shows: find.text(pl.fmFolderName),
  );

  // --- File action sheets, one per shape ---

  for (final (name, folder, what) in [
    (_plate12, 1, 'sliced: print and preview'),
    (_crimper, null, 'a 3MF source: slice and pipeline'),
    (_rails, null, 'an STL source'),
    (_step, null, 'a STEP source, no thumbnail'),
  ]) {
    a11ySurface(
      'library file sheet, $name ($what)',
      home: () => FileManagerScreen(folderId: folder),
      arrange: (tester) => a11yTap(tester, find.text(name)),
      shows: byLogId('file_actions.add_to_queue'),
    );
  }

  a11ySurface(
    'library file sheet, tags offered',
    overrides: _withTags,
    home: () => const FileManagerScreen(),
    arrange: (tester) => a11yTap(tester, find.text(_crimper)),
    shows: byLogId('file_actions.tags'),
  );

  // --- The hand-built listing ---

  a11ySurface(
    'library, every row variant',
    overrides: layerOverrides([..._sinkListing], _withTags),
    home: () => const FileManagerScreen(),
    shows: find.text('Mounted share'),
  );

  a11ySurface(
    'library file sheet, variants, tags, photos and a link',
    overrides: layerOverrides([..._sinkListing], _withTags),
    home: () => const FileManagerScreen(),
    arrange: (tester) => a11yTap(tester, find.text(_sinkPlate12)),
    shows: byLogId('file_actions.queue_variants'),
  );

  a11ySurface(
    'library file sheet, a file on an external mount',
    overrides: _sinkListing,
    home: () => const FileManagerScreen(),
    arrange: (tester) => a11yTap(tester, find.text('Bag dispenser.gcode.3mf')),
    shows: byLogId('file_actions.add_to_queue'),
  );

  a11ySurface(
    'library file sheet, a long name',
    overrides: _sinkListing,
    home: () => const FileManagerScreen(),
    arrange: (tester) => a11yTap(tester, find.text(_longName)),
    shows: byLogId('file_actions.add_to_queue'),
  );

  a11ySurface(
    'library, folder menu',
    overrides: _sinkListing,
    home: () => const FileManagerScreen(),
    arrange: (tester) => a11yTap(tester, byLogId('files.folder_actions')),
    shows: byLogId('files.folder.rename'),
  );

  // --- States with nothing to list ---

  a11ySurface(
    'library, empty',
    overrides: [
      fileManagerProvider.overrideWith(
        () => _Listing(const FileManagerState()),
      ),
    ],
    home: () => const FileManagerScreen(),
    shows: find.text(pl.fmEmpty),
  );

  a11ySurface(
    'library, a search that matches nothing',
    overrides: [
      fileManagerProvider.overrideWith(
        () => _Listing(
          FileManagerState(files: _kitchenSink.files, query: 'zzzz'),
        ),
      ),
    ],
    home: () => const FileManagerScreen(),
    shows: find.text(pl.fmNoMatches),
  );

  a11ySurface(
    'library, the library-wide fetch failed',
    overrides: [
      fileManagerProvider.overrideWith(
        () => _Listing(const FileManagerState(fetchFailed: true)),
      ),
    ],
    home: () => const FileManagerScreen(),
    shows: find.text(pl.connectFailed),
  );

  a11ySurface(
    'library, a library-wide fetch in flight',
    overrides: [
      fileManagerProvider.overrideWith(
        () => _Listing(const FileManagerState(searching: true, query: 'rack')),
      ),
    ],
    home: () => const FileManagerScreen(),
    shows: find.byType(DashLoading),
  );

  a11ySurface(
    'library, a folder the user cannot write to',
    overrides: [
      fileManagerProvider.overrideWith(
        () => _Listing(
          FileManagerState(
            allFolders: _kitchenSink.allFolders,
            currentFolderId: 3,
          ),
        ),
      ),
    ],
    home: () => const FileManagerScreen(),
    shows: find.text(pl.fmEmpty),
  );

  // --- Confirmations, prompts and pickers of the library ---

  a11ySurface(
    'library delete file dialog',
    home: () => const FileManagerScreen(folderId: 1),
    arrange: (tester) async {
      await a11yTap(tester, find.text(_plate12));
      await a11yTap(tester, byLogId('file_actions.delete'));
    },
    shows: byLogId('files.delete_confirm.confirm'),
  );

  a11ySurface(
    'library rename file prompt',
    home: () => const FileManagerScreen(folderId: 1),
    arrange: (tester) async {
      await a11yTap(tester, find.text(_plate12));
      await a11yTap(tester, byLogId('file_actions.rename'));
    },
    shows: find.text(pl.fmFileName),
  );

  a11ySurface(
    'library move sheet',
    home: () => const FileManagerScreen(folderId: 1),
    arrange: (tester) async {
      await a11yTap(tester, find.text(_plate12));
      await a11yTap(tester, byLogId('file_actions.move'));
    },
    shows: byLogId('files.move_target_root'),
  );

  a11ySurface(
    'library delete folder dialog',
    home: () => const FileManagerScreen(),
    arrange: (tester) async {
      await a11yTap(tester, byLogId('files.folder_actions'));
      await a11yTap(tester, byLogId('files.folder.delete'));
    },
    shows: byLogId('files.folder_delete_confirm.confirm'),
  );

  a11ySurface(
    'library rename folder prompt',
    home: () => const FileManagerScreen(),
    arrange: (tester) async {
      await a11yTap(tester, byLogId('files.folder_actions'));
      await a11yTap(tester, byLogId('files.folder.rename'));
    },
    shows: find.text(pl.fmRenameFolder),
  );

  a11ySurface(
    'library bulk delete dialog',
    home: () => const FileManagerScreen(),
    arrange: (tester) async {
      await a11yLongPress(tester, find.text(_crimper));
      await a11yTap(tester, byLogId('files.delete_selected'));
    },
    shows: byLogId('files.bulk_delete_confirm.confirm'),
  );

  // The demo has billing on, so a bulk add asks for a cost center first and
  // then, where the server can take one, for the printer. Two files: a single
  // one on a billing server opens the print form instead (the queue's file).
  a11ySurface(
    'library bulk add, cost center sheet',
    home: () => const FileManagerScreen(folderId: 1),
    arrange: (tester) async {
      await a11yLongPress(tester, find.text(_plate12));
      await a11yTap(tester, find.text(_plate13));
      await a11yTap(tester, byLogId('files.add_to_queue'));
    },
    shows: byLogId('sheet.queue_cost_center'),
  );

  a11ySurface(
    'library bulk add, printer sheet',
    home: () => const FileManagerScreen(folderId: 1),
    arrange: (tester) async {
      await a11yLongPress(tester, find.text(_plate12));
      await a11yTap(tester, find.text(_plate13));
      await a11yTap(tester, byLogId('files.add_to_queue'));
      await a11yTap(tester, byLogId('queue_cost_center.center'));
    },
    shows: byLogId('sheet.queue_target'),
  );

  a11ySurface(
    'library bulk add, cost center sheet with a personal center',
    demo: false,
    home: () => A11yLauncher(
      (context) => showQueueCostCenterSheet(
        context,
        jobCount: 3,
        centers: const [
          CostCenter(id: 1, name: 'demo', isPrivate: true),
          CostCenter(id: 2, name: 'Workshop'),
        ],
      ),
    ),
    arrange: a11yOpenLauncher,
    shows: byLogId('sheet.queue_cost_center'),
  );

  a11ySurface(
    'library bulk add, printer sheet with models',
    demo: false,
    home: () => A11yLauncher(
      (context) => showQueueTargetSheet(
        context,
        fileCount: 3,
        printers: const [
          Printer(id: 1, name: 'X1C-01', model: 'X1C'),
          Printer(id: 2, name: 'P1S-02', model: 'P1S'),
          Printer(id: 3, name: 'Spare', model: 'P1S', isActive: false),
        ],
      ),
    ),
    arrange: a11yOpenLauncher,
    shows: byLogId('sheet.queue_target'),
  );

  a11ySurface(
    'library bulk variant grouping, selection of two',
    home: () => const FileManagerScreen(folderId: 1),
    arrange: (tester) async {
      await a11yLongPress(tester, find.text(_plate12));
      await a11yTap(tester, find.text('Server rack – plate 14'));
    },
    shows: byLogId('files.group_variants'),
  );

  // --- Tags ---

  a11ySurface(
    'library, tag filter in the search bar',
    overrides: _withTags,
    home: () => const FileManagerScreen(),
    shows: byLogId('files.tag_filter'),
  );

  a11ySurface(
    'tag filter sheet',
    overrides: _withTags,
    home: () => const FileManagerScreen(),
    arrange: (tester) => a11yTap(tester, byLogId('files.tag_filter')),
    shows: find.text(pl.fmTagsFilterTitle),
  );

  a11ySurface(
    'tag filter sheet, two chosen',
    overrides: _withTags,
    home: () => const FileManagerScreen(),
    arrange: (tester) async {
      await a11yTap(tester, byLogId('files.tag_filter'));
      await a11yTap(tester, find.text('rack'));
      await a11yTap(tester, find.text('PETG'));
    },
    shows: byLogId('tag_filter.clear'),
  );

  a11ySurface(
    'tag filter sheet, new tag prompt',
    overrides: _withTags,
    home: () => const FileManagerScreen(),
    arrange: (tester) async {
      await a11yTap(tester, byLogId('files.tag_filter'));
      await a11yTap(tester, byLogId('tag_filter.new'));
    },
    shows: find.text(pl.fmTagName),
  );

  a11ySurface(
    'tag filter sheet, empty catalog',
    overrides: [
      libraryTagsSupportedProvider.overrideWithValue(const AsyncData(true)),
      libraryTagsProvider.overrideWith((ref) async => const <LibraryTag>[]),
    ],
    home: () => const FileManagerScreen(),
    arrange: (tester) => a11yTap(tester, byLogId('files.tag_filter')),
    shows: find.text(pl.fmTagsEmpty),
  );

  a11ySurface(
    'tag filter sheet, catalog failed to load',
    overrides: [
      libraryTagsSupportedProvider.overrideWithValue(const AsyncData(true)),
      libraryTagsProvider.overrideWith(
        (ref) async => throw const ApiException(AppErrorCode.serverUnreachable),
      ),
    ],
    home: () => const FileManagerScreen(),
    arrange: (tester) => a11yTap(tester, byLogId('files.tag_filter')),
    shows: find.text(pl.connectFailed),
  );

  a11ySurface(
    'tag manage sheet',
    overrides: _withTags,
    home: () => const FileManagerScreen(),
    arrange: (tester) async {
      await a11yTap(tester, byLogId('files.tag_filter'));
      await a11yTap(tester, byLogId('tag_filter.manage'));
    },
    shows: find.text(pl.fmTagsManage),
  );

  a11ySurface(
    'tag manage sheet, tag menu',
    overrides: _withTags,
    home: () => const FileManagerScreen(),
    arrange: (tester) async {
      await a11yTap(tester, byLogId('files.tag_filter'));
      await a11yTap(tester, byLogId('tag_filter.manage'));
      await a11yTap(tester, byLogId('tag_manage.actions'));
    },
    shows: byLogId('tag_manage.rename'),
  );

  a11ySurface(
    'tag manage sheet, rename prompt',
    overrides: _withTags,
    home: () => const FileManagerScreen(),
    arrange: (tester) async {
      await a11yTap(tester, byLogId('files.tag_filter'));
      await a11yTap(tester, byLogId('tag_filter.manage'));
      await a11yTap(tester, byLogId('tag_manage.actions'));
      await a11yTap(tester, byLogId('tag_manage.rename'));
    },
    shows: find.text(pl.fmTagRename),
  );

  a11ySurface(
    'tag manage sheet, delete dialog',
    overrides: _withTags,
    home: () => const FileManagerScreen(),
    arrange: (tester) async {
      await a11yTap(tester, byLogId('files.tag_filter'));
      await a11yTap(tester, byLogId('tag_filter.manage'));
      await a11yTap(tester, byLogId('tag_manage.actions'));
      await a11yTap(tester, byLogId('tag_manage.delete'));
    },
    shows: byLogId('tag_manage.delete_confirm.confirm'),
  );

  a11ySurface(
    'file tags sheet',
    overrides: layerOverrides([..._sinkListing], _withTags),
    home: () => const FileManagerScreen(),
    arrange: (tester) async {
      await a11yTap(tester, find.text(_sinkPlate12));
      await a11yTap(tester, byLogId('file_actions.tags'));
    },
    shows: byLogId('file_tags.save'),
  );

  a11ySurface(
    'bulk tags sheet',
    overrides: _withTags,
    home: () => const FileManagerScreen(),
    arrange: (tester) async {
      await a11yLongPress(tester, find.text(_crimper));
      await a11yTap(tester, byLogId('files.tag_selected'));
    },
    shows: byLogId('bulk_tags.add'),
  );

  a11ySurface(
    'bulk tags sheet, tags ticked',
    overrides: _withTags,
    home: () => const FileManagerScreen(),
    arrange: (tester) async {
      await a11yLongPress(tester, find.text(_crimper));
      await a11yTap(tester, byLogId('files.tag_selected'));
      await a11yTap(tester, find.text('gift'));
    },
    shows: byLogId('bulk_tags.add'),
  );

  a11ySurface(
    'bulk tags sheet, replace dialog',
    overrides: _withTags,
    home: () => const FileManagerScreen(),
    arrange: (tester) async {
      await a11yLongPress(tester, find.text(_crimper));
      await a11yTap(tester, byLogId('files.tag_selected'));
      await a11yTap(tester, byLogId('bulk_tags.replace'));
    },
    shows: byLogId('bulk_tags.replace_confirm.confirm'),
  );

  // --- Trash ---

  a11ySurface(
    'trash, empty',
    home: () => const TrashScreen(),
    shows: find.text(pl.fmTrashEmpty),
  );

  final trashed = libraryTrashProvider.overrideWith(
    (ref) async => [
      TrashFile(
        id: 1,
        filename: 'Server rack – plate 13.gcode.3mf',
        fileSize: 812340,
        folderName: 'Server rack',
        deletedAt: DateTime(2026, 10, 20),
      ),
      const TrashFile(id: 2, filename: 'Crimper 24 mm.3mf', fileSize: 634212),
    ],
  );

  a11ySurface(
    'trash',
    overrides: [trashed],
    home: () => const TrashScreen(),
    shows: find.text('Crimper 24 mm.3mf'),
  );

  a11ySurface(
    'trash, failed to load',
    overrides: [
      libraryTrashProvider.overrideWith(
        (ref) async => throw const ApiException(AppErrorCode.serverUnreachable),
      ),
    ],
    home: () => const TrashScreen(),
    shows: find.text(pl.retry),
  );

  a11ySurface(
    'trash, delete forever dialog',
    overrides: [trashed],
    home: () => const TrashScreen(),
    arrange: (tester) => a11yTap(tester, byLogId('trash.delete')),
    shows: byLogId('trash.hard_delete_confirm.confirm'),
  );

  a11ySurface(
    'trash, empty trash dialog',
    overrides: [trashed],
    home: () => const TrashScreen(),
    arrange: (tester) => a11yTap(tester, byLogId('trash.purge')),
    shows: byLogId('trash.purge_confirm.confirm'),
  );

  // --- File details and its photos ---

  const detail = LibraryFileDetail(
    externalUrl: 'https://www.printables.com/model/12345-server-rack',
    sourceUrl: 'https://makerworld.com/models/1',
    notes: 'Printed in PETG at 250 degrees, the lids need the brim.',
    photos: ['a1.jpg', 'b2.jpg', 'c3.jpg'],
  );
  final withDetail = libraryFileDetailProvider(
    1,
  ).overrideWith((ref) async => detail);

  a11ySurface(
    'file details',
    overrides: [withDetail],
    home: () => const FileDetailsScreen(fileId: 1, title: _plate12),
    shows: find.text(detail.notes!),
  );

  a11ySurface(
    'file details, nothing added yet',
    shows: find.text(pl.fmPhotosEmpty),
    home: () => const FileDetailsScreen(fileId: 1, title: _plate12),
  );

  a11ySurface(
    'file details, photo source sheet',
    overrides: [withDetail],
    home: () => const FileDetailsScreen(fileId: 1, title: _plate12),
    arrange: (tester) => a11yTap(tester, byLogId('file_details.add_photo')),
    shows: byLogId('sheet.photo_source'),
  );

  a11ySurface(
    'file details, link prompt',
    overrides: [withDetail],
    home: () => const FileDetailsScreen(fileId: 1, title: _plate12),
    arrange: (tester) => a11yTap(tester, byLogId('file_details.edit_link')),
    shows: find.text(pl.fmLinkField),
  );

  a11ySurface(
    'file details, notes prompt',
    overrides: [withDetail],
    home: () => const FileDetailsScreen(fileId: 1, title: _plate12),
    arrange: (tester) => a11yTap(tester, byLogId('file_details.edit_notes')),
    shows: find.text(pl.fmNotes),
  );

  a11ySurface(
    'file details, failed to load',
    overrides: [
      libraryFileDetailProvider(1).overrideWith(
        (ref) async => throw const ApiException(AppErrorCode.serverUnreachable),
      ),
    ],
    home: () => const FileDetailsScreen(fileId: 1, title: _plate12),
    shows: find.text(pl.retry),
  );

  a11ySurface(
    'file photos',
    overrides: [withDetail],
    home: () => const FilePhotosScreen(fileId: 1, title: _plate12),
    shows: byLogId('file_photos.delete'),
  );

  a11ySurface(
    'file photos, delete dialog',
    overrides: [withDetail],
    home: () => const FilePhotosScreen(fileId: 1, title: _plate12),
    arrange: (tester) => a11yTap(tester, byLogId('file_photos.delete')),
    shows: byLogId('file_photos.delete.confirm'),
  );

  a11ySurface(
    'file photos, none',
    home: () => const FilePhotosScreen(fileId: 1, title: _plate12),
    shows: find.text(pl.fmPhotosEmpty),
  );

  // --- The printer's own file manager ---

  const printerScreen = PrinterFileManagerScreen(
    printerId: 1,
    printerName: 'X1C-01',
  );

  a11ySurface(
    'printer files',
    home: () => printerScreen,
    shows: find.text('Bag dispenser.gcode.3mf'),
  );

  a11ySurface(
    'printer files, cache folder',
    home: () => printerScreen,
    arrange: (tester) => a11yTap(tester, find.text(pl.pfmTabCache)),
    shows: find.text('Mikrus slot.gcode.3mf'),
  );

  a11ySurface(
    'printer files, timelapse folder',
    home: () => printerScreen,
    arrange: (tester) => a11yTap(tester, find.text(pl.pfmTabTimelapse)),
    shows: find.byIcon(Icons.movie_outlined),
  );

  a11ySurface(
    'printer files, empty folder',
    home: () => printerScreen,
    arrange: (tester) => a11yTap(tester, find.text(pl.pfmTabModels)),
    shows: find.text(pl.pfmEmpty),
  );

  a11ySurface(
    'printer files, search with no matches',
    home: () => printerScreen,
    arrange: (tester) async {
      await tester.enterText(find.byType(TextField).first, 'zzzz');
      await a11ySettle(tester, const Duration(seconds: 1));
    },
    shows: find.text(pl.pfmNoMatches),
  );

  a11ySurface(
    'printer files, sort menu',
    home: () => printerScreen,
    arrange: (tester) => a11yTap(tester, byLogId('printer_files.sort')),
    shows: find.text(pl.pfmSortNameAsc),
  );

  a11ySurface(
    'printer files, selection and action bar',
    home: () => printerScreen,
    arrange: (tester) async {
      await a11yTap(tester, find.text(pl.pfmTabCache));
      await a11yTap(tester, byLogId('printer_files.select_all'));
    },
    shows: byLogId('printer_files.download'),
  );

  a11ySurface(
    'printer files, delete dialog',
    home: () => printerScreen,
    arrange: (tester) async {
      await a11yTap(tester, find.text(pl.pfmTabCache));
      await a11yTap(tester, byLogId('printer_files.select_all'));
      await a11yTap(tester, byLogId('printer_files.delete'));
    },
    shows: byLogId('printer_files_delete.confirm'),
  );

  a11ySurface(
    'printer files, download preparing',
    overrides: [heldDownloadOverride],
    home: () => printerScreen,
    arrange: (tester) async {
      await a11yTap(tester, find.text(pl.pfmTabCache));
      await a11yTap(tester, byLogId('printer_files.select_all'));
      await a11yTap(tester, byLogId('printer_files.download'));
      await a11ySettle(tester, const Duration(seconds: 1));
    },
    shows: byLogId('printer_files.download_cancel'),
  );

  a11ySurface(
    'printer files, printer did not answer',
    demo: false,
    overrides: [
      printerFilesRepositoryProvider.overrideWithValue(
        _FixedPrinterFiles(
          listing: const PrinterFileListing(printerUnavailable: true),
        ),
      ),
    ],
    home: () => printerScreen,
    shows: find.text(pl.pfmPrinterUnavailable),
  );

  a11ySurface(
    'printer files, listing refused',
    demo: false,
    overrides: [
      printerFilesRepositoryProvider.overrideWithValue(
        _FixedPrinterFiles(
          fails: const ApiException(AppErrorCode.serverUnreachable),
        ),
      ),
    ],
    home: () => printerScreen,
    shows: byLogId('printer_files.retry'),
  );

  a11ySurface(
    'printer files, files with long names and no dates',
    demo: false,
    overrides: [
      printerFilesRepositoryProvider.overrideWithValue(
        _FixedPrinterFiles(
          listing: const PrinterFileListing(
            files: [
              PrinterFile(
                name:
                    'a_really_long_file_name_without_any_spaces_in_it.gcode.3mf',
                path: '/a.gcode.3mf',
                isDirectory: false,
                size: 123456789,
              ),
              PrinterFile(
                name: 'notes.txt',
                path: '/notes.txt',
                isDirectory: false,
                size: 12,
              ),
              PrinterFile(
                name: 'photo.png',
                path: '/photo.png',
                isDirectory: false,
                size: 4096,
              ),
              PrinterFile(
                name: 'logs',
                path: '/logs',
                isDirectory: true,
                size: 0,
              ),
            ],
          ),
        ),
      ),
    ],
    home: () => printerScreen,
    shows: find.text('notes.txt'),
  );
}
