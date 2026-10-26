import 'dart:async';

import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/makerworld.dart';
import 'package:bambuddy_mobile/core/models/manyfold.dart';
import 'package:bambuddy_mobile/core/theme/dash_theme.dart';
import 'package:bambuddy_mobile/data/makerworld_repository.dart';
import 'package:bambuddy_mobile/features/makerworld/makerworld_providers.dart';
import 'package:bambuddy_mobile/features/manyfold/manyfold_connection.dart';
import 'package:bambuddy_mobile/features/manyfold/manyfold_model_screen.dart';
import 'package:bambuddy_mobile/features/manyfold/manyfold_providers.dart';
import 'package:bambuddy_mobile/features/manyfold/manyfold_tab.dart';
import 'package:bambuddy_mobile/features/model_sources/model_sources_screen.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers.dart';
import 'a11y_harness.dart';

/// Rendered contrast and touch targets for Model Sources and the two tabs under
/// it (`lib/features/model_sources/`, `makerworld/`, `manyfold/`): MakerWorld
/// signed out and in, with a resolved model (few plates, many plates, an
/// imported plate and its snack, loading, failed); Manyfold's grid, selection,
/// paging, empty search, failure, connection form (test result, disconnect
/// dialog, not connected) and the model screen (importable, imported and
/// not-importable files, selection, no files, failure). The demo backend serves
/// a connected Manyfold; MakerWorld's resolve and import answer from a mock
/// dio, because the demo has no MakerWorld model. Not covered: the browser
/// behind "Open on MakerWorld" and "Open in Manyfold", and the cloud sign-in
/// screen the banner navigates to (settings, not this slice).
void main() {
  group('Model Sources', () {
    a11ySurface(
      'model sources, MakerWorld tab, signed out',
      home: () => const ModelSourcesScreen(),
      shows: find.text(pl.mwLoginRequired),
    );

    a11ySurface(
      'model sources, without a Manyfold tab',
      home: () => const ModelSourcesScreen(),
      overrides: [manyfoldStatusProvider.overrideWith((ref) async => null)],
      shows: find.text(pl.mwIntro),
    );
  });

  group('MakerWorld', () {
    final signedIn = [
      makerworldStatusProvider.overrideWith(
        (ref) async =>
            const MakerWorldStatus(hasCloudToken: true, canDownload: true),
      ),
    ];

    a11ySurface(
      'makerworld, signed in with recent imports',
      home: () => const ModelSourcesScreen(),
      overrides: [
        ...signedIn,
        makerworldRecentImportsProvider.overrideWith(
          (ref) async => const [
            MakerWorldRecentImport(
              libraryFileId: 3,
              filename: 'Articulated dragon.3mf',
              sourceUrl: 'https://makerworld.com/models/7',
            ),
            MakerWorldRecentImport(
              libraryFileId: 4,
              filename: 'Filament swatch box.3mf',
            ),
          ],
        ),
      ],
      shows: find.text('Articulated dragon.3mf'),
    );

    a11ySurface(
      'makerworld, empty address',
      home: () => const ModelSourcesScreen(),
      overrides: signedIn,
      arrange: (tester) async {
        await tester.tap(byLogId('makerworld.resolve'));
      },
      shows: find.text(pl.mwEnterUrl),
    );

    a11ySurface(
      'makerworld, resolved model',
      home: () => const ModelSourcesScreen(),
      overrides: [
        ...signedIn,
        makerworldResolveProvider.overrideWith(() => _Resolved(_model(3))),
      ],
      shows: find.text('Mug Holder'),
    );

    a11ySurface(
      'makerworld, resolved model without plates',
      home: () => const ModelSourcesScreen(),
      overrides: [
        ...signedIn,
        makerworldResolveProvider.overrideWith(() => _Resolved(_model(0))),
      ],
      shows: find.text(pl.mwNoPlates),
    );

    a11ySurface(
      'makerworld, resolved model, collapsed plates',
      home: () => const ModelSourcesScreen(),
      overrides: [
        ...signedIn,
        makerworldResolveProvider.overrideWith(() => _Resolved(_model(8))),
      ],
      shows: byLogId('makerworld.toggle_plates'),
    );

    a11ySurface(
      'makerworld, resolved model, every plate',
      home: () => const ModelSourcesScreen(),
      overrides: [
        ...signedIn,
        makerworldResolveProvider.overrideWith(() => _Resolved(_model(8))),
      ],
      arrange: (tester) async {
        await tester.tap(byLogId('makerworld.toggle_plates'));
      },
      shows: find.text(pl.mwShowLess),
    );

    a11ySurface(
      'makerworld, resolving',
      home: () => const ModelSourcesScreen(),
      overrides: [
        ...signedIn,
        makerworldResolveProvider.overrideWith(_Busy.new),
      ],
      shows: byLogId('makerworld.resolve'),
    );

    a11ySurface(
      'makerworld, resolve failed',
      home: () => const ModelSourcesScreen(),
      overrides: [
        ...signedIn,
        makerworldResolveProvider.overrideWith(_Refused.new),
      ],
      shows: byLogId('makerworld.error_action'),
    );

    // The import goes to a mock dio: it leaves the "In library" badge and the
    // snack bar with its action on screen.
    a11ySurface(
      'makerworld, plate imported',
      demo: false,
      home: () => const ModelSourcesScreen(),
      overrides: [
        fakeServerProfileOverride(),
        makerworldRepositoryProvider.overrideWithValue(
          MakerWorldRepository(_importDio()),
        ),
        ...signedIn,
        makerworldRecentImportsProvider.overrideWith((ref) async => const []),
        manyfoldStatusProvider.overrideWith((ref) async => null),
      ],
      arrange: (tester) async {
        await tester.enterText(
          find.byType(TextField),
          'https://makerworld.com/models/7',
        );
        await tester.tap(byLogId('makerworld.resolve'));
        await a11ySettle(tester, const Duration(seconds: 1));
        await tester.tap(byLogId('makerworld.import_plate').first);
        await a11ySettle(tester, const Duration(seconds: 1));
      },
      shows: find.text(pl.mwInLibrary),
    );
  });

  group('Manyfold tab', () {
    Future<void> openTab(WidgetTester tester) async {
      await tester.tap(byLogId('model_sources.tab_manyfold'));
      await a11ySettle(tester, const Duration(seconds: 1));
    }

    a11ySurface(
      'manyfold, models',
      home: () => const ModelSourcesScreen(),
      arrange: openTab,
      shows: find.text('Articulated dragon'),
    );

    a11ySurface(
      'manyfold, models ticked',
      home: () => const ModelSourcesScreen(),
      arrange: (tester) async {
        await openTab(tester);
        await tester.tap(byLogId('manyfold.select_page'));
        await a11ySettle(tester, const Duration(seconds: 1));
      },
      shows: byLogId('manyfold.import_models'),
    );

    a11ySurface(
      'manyfold, import folder select open',
      home: () => const ModelSourcesScreen(),
      arrange: (tester) async {
        await openTab(tester);
        await tester.tap(byLogId('manyfold.select_page'));
        await a11ySettle(tester, const Duration(seconds: 1));
        await tester.tap(byLogId('manyfold.import_folder'));
      },
      shows: byLogId('manyfold.folder_auto'),
    );

    a11ySurface(
      'manyfold, second page',
      home: () => const ModelSourcesScreen(),
      arrange: (tester) async {
        await openTab(tester);
        await tester.tap(byLogId('manyfold.next_page'));
        await a11ySettle(tester, const Duration(seconds: 1));
      },
      shows: find.text('Lithophane frame'),
    );

    a11ySurface(
      'manyfold, no models',
      home: () => const ModelSourcesScreen(),
      overrides: [
        manyfoldModelsProvider.overrideWith(
          (ref, key) async => const ManyfoldModelPage(
            total: 0,
            page: 1,
            hasNext: false,
            hasPrevious: false,
            models: [],
          ),
        ),
      ],
      arrange: openTab,
      shows: find.text(pl.mfNoModels),
    );

    a11ySurface(
      'manyfold, listing failed',
      home: () => const ModelSourcesScreen(),
      overrides: [
        manyfoldModelsProvider.overrideWith(
          (ref, key) async => throw const ManyfoldFailure(
            'manyfold_unreachable',
            ApiException(AppErrorCode.serverUnreachable),
          ),
        ),
      ],
      arrange: openTab,
      shows: find.text(pl.mfErrUnreachable),
    );

    a11ySurface(
      'manyfold, connection form over a working connection',
      home: () => const ModelSourcesScreen(),
      arrange: (tester) async {
        await openTab(tester);
        await tester.tap(byLogId('manyfold.edit_connection'));
        await a11ySettle(tester, const Duration(seconds: 1));
      },
      shows: byLogId('manyfold.disconnect'),
    );

    a11ySurface(
      'manyfold, connection test passed',
      home: () => const ModelSourcesScreen(),
      arrange: (tester) async {
        await openTab(tester);
        await tester.tap(byLogId('manyfold.edit_connection'));
        await a11ySettle(tester, const Duration(seconds: 1));
        await tester.tap(byLogId('manyfold.test'));
        await a11ySettle(tester, const Duration(seconds: 1));
      },
      shows: find.text(pl.mfTestOk(5)),
    );

    a11ySurface(
      'manyfold, connection test refused',
      home: () => const ModelSourcesScreen(),
      arrange: (tester) async {
        await openTab(tester);
        await tester.tap(byLogId('manyfold.edit_connection'));
        await a11ySettle(tester, const Duration(seconds: 1));
        await tester.enterText(
          find.descendant(
            of: byLogId('manyfold.url'),
            matching: find.byType(TextField),
          ),
          'ftp://library.local',
        );
        await tester.pump();
        await tester.tap(byLogId('manyfold.test'));
        await a11ySettle(tester, const Duration(seconds: 1));
      },
      shows: find.text(pl.mfErrBadUrl),
    );

    a11ySurface(
      'manyfold, disconnect confirmation',
      home: () => const ModelSourcesScreen(),
      arrange: (tester) async {
        await openTab(tester);
        await tester.tap(byLogId('manyfold.edit_connection'));
        await a11ySettle(tester, const Duration(seconds: 1));
        await tester.tap(byLogId('manyfold.disconnect'));
      },
      shows: find.text(pl.mfDisconnectTitle),
    );

    // Not connected yet, by someone who may connect it: the tab shows the form.
    a11ySurface(
      'manyfold, not connected, connection form',
      home: () => const ModelSourcesScreen(),
      overrides: [
        manyfoldStatusProvider.overrideWith(
          (ref) async => const ManyfoldStatus(configured: false),
        ),
        manyfoldConfigProvider.overrideWith(
          (ref) async => const ManyfoldConfig(),
        ),
      ],
      arrange: openTab,
      shows: byLogId('manyfold.url'),
    );

    // Not reachable through Model Sources (the tab hides itself), only by
    // losing the permission while the tab is open, so the tab is hosted alone.
    a11ySurface(
      'manyfold, not connected, nobody to connect it',
      home: () => const DashBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: ManyfoldTab(status: ManyfoldStatus(configured: false)),
        ),
      ),
      overrides: [canConfigureManyfoldProvider.overrideWithValue(false)],
      shows: find.text(pl.mfNotConnectedTitle),
    );
  });

  group('Manyfold model', () {
    Widget modelScreen(String id, String title) =>
        ManyfoldModelScreen(modelId: id, title: title);

    a11ySurface(
      'manyfold model, files',
      home: () => modelScreen('k3x9pq2a', 'Articulated dragon'),
      shows: find.text('dragon.3mf'),
    );

    a11ySurface(
      'manyfold model, files ticked',
      home: () => modelScreen('k3x9pq2a', 'Articulated dragon'),
      arrange: (tester) async {
        await tester.tap(byLogId('manyfold.select_all'));
        await a11ySettle(tester, const Duration(seconds: 1));
      },
      shows: byLogId('manyfold.import_selected'),
    );

    a11ySurface(
      'manyfold model, import folder select open',
      home: () => modelScreen('k3x9pq2a', 'Articulated dragon'),
      arrange: (tester) async {
        await tester.tap(byLogId('manyfold.import_folder'));
      },
      shows: byLogId('manyfold.folder_auto'),
    );

    // The model as the server reads it once a file is in the library; set
    // here rather than by tapping Import, which would change the demo's
    // library for every surface that runs after it.
    a11ySurface(
      'manyfold model, one file in the library',
      home: () => modelScreen('k3x9pq2a', 'Articulated dragon'),
      overrides: [
        manyfoldModelProvider.overrideWith(
          (ref, id) async => const ManyfoldModel(
            id: 'k3x9pq2a',
            name: 'Articulated dragon',
            caption: 'Print-in-place, no supports',
            license: 'CC-BY-4.0',
            tags: ['articulated', 'toy'],
            url: 'http://192.168.1.50:3214/models/k3x9pq2a',
            files: [
              ManyfoldFile(
                id: 'f1dragon',
                name: 'dragon.3mf',
                mime: 'model/3mf',
                importable: true,
                libraryFile: ManyfoldLibraryRef(
                  id: 3,
                  filename: 'dragon.3mf',
                  folderId: 5,
                ),
              ),
              ManyfoldFile(
                id: 'f2tail',
                name: 'dragon_tail_long.stl',
                mime: 'model/stl',
                importable: true,
              ),
              ManyfoldFile(
                id: 'f3readme',
                name: 'README.pdf',
                mime: 'application/pdf',
              ),
            ],
          ),
        ),
      ],
      shows: find.text(pl.mfInLibrary),
    );

    a11ySurface(
      'manyfold model, no description and no tags',
      home: () => modelScreen('p4w8ze1c', 'Desk cable tray'),
      shows: find.text('cable_tray.3mf'),
    );

    a11ySurface(
      'manyfold model, no files',
      home: () => modelScreen('z9c1fk5u', 'Lithophane frame'),
      shows: find.text(pl.mfNoFiles),
    );

    a11ySurface(
      'manyfold model, not found',
      home: () => modelScreen('missing', 'Gone'),
      shows: find.text(pl.mfErrNotFound),
    );
  });
}

/// Seven plates make the list collapse behind "Show all".
MakerWorldResolvedModel _model(int plates) => MakerWorldResolvedModel(
  modelId: 7,
  design: const MakerWorldDesign(title: 'Mug Holder'),
  instances: [
    for (var i = 1; i <= plates; i++)
      MakerWorldInstance(profileId: 10 + i, name: 'Plate $i · 0.2 mm Standard'),
  ],
);

class _Resolved extends MakerWorldResolveNotifier {
  _Resolved(this.model);

  final MakerWorldResolvedModel model;

  @override
  Future<MakerWorldResolvedModel?> build() async => model;
}

/// A resolve that never answers.
class _Busy extends MakerWorldResolveNotifier {
  @override
  Future<MakerWorldResolvedModel?> build() =>
      Completer<MakerWorldResolvedModel?>().future;
}

class _Refused extends MakerWorldResolveNotifier {
  @override
  Future<MakerWorldResolvedModel?> build() async =>
      throw const ApiException(AppErrorCode.malformedResponse);
}

Dio _importDio() {
  final dio = testDio();
  mockServer(dio)
    ..onPost(
      '/api/v1/makerworld/resolve',
      (s) => s.reply(200, {
        'model_id': 7,
        'design': {'title': 'Mug Holder'},
        'instances': [
          {'profile_id': 11, 'name': 'Plate 1'},
        ],
      }),
      data: {'url': 'https://makerworld.com/models/7'},
    )
    ..onPost(
      '/api/v1/makerworld/import',
      (s) => s.reply(200, {'library_file_id': 3, 'filename': 'mug.3mf'}),
      data: {'model_id': 7, 'profile_id': 11},
    );
  return dio;
}
