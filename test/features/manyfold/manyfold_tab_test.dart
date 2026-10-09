import 'package:bambuddy_mobile/core/models/current_user.dart';
import 'package:bambuddy_mobile/core/models/makerworld.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/data/library_repository.dart';
import 'package:bambuddy_mobile/data/manyfold_repository.dart';
import 'package:bambuddy_mobile/features/manyfold/manyfold_model_screen.dart';
import 'package:bambuddy_mobile/features/model_sources/model_sources_screen.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../../helpers.dart';

void main() {
  late DioAdapter server;
  late List<Override> overrides;

  AppLocalizations l10n(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(Scaffold).first));

  CurrentUser user(Set<String> permissions) => CurrentUser(
    id: 2,
    username: 'ola',
    isAdmin: false,
    permissions: permissions,
  );

  setUp(() {
    final dio = testDio();
    server = mockServer(dio)
      ..onGet('/api/v1/library/folders', (s) => s.reply(200, <Object>[]));
    overrides = [
      fakeServerProfileOverride(authMode: AuthMode.jwt),
      manyfoldRepositoryProvider.overrideWithValue(ManyfoldRepository(dio)),
      libraryRepositoryProvider.overrideWithValue(LibraryRepository(dio)),
      makerworldStatusProvider.overrideWith(
        (ref) async =>
            const MakerWorldStatus(hasCloudToken: true, canDownload: true),
      ),
      makerworldRecentImportsProvider.overrideWith((ref) async => const []),
    ];
  });

  void status(int code, [Map<String, dynamic>? body]) => server.onGet(
    '/api/v1/manyfold/status',
    (s) => s.reply(code, body ?? {'detail': 'Not Found'}),
  );

  void listing() => server
    ..onGet(
      '/api/v1/manyfold/models',
      (s) => s.reply(200, {
        'total': 2,
        'page': 1,
        'has_next': false,
        'has_previous': false,
        'models': [
          {'id': 'm1', 'name': 'Dragon'},
          {'id': 'm2', 'name': 'Swatch box'},
        ],
      }),
      queryParameters: {'q': '', 'page': 1},
    )
    ..onGet('/api/v1/manyfold/models/m1/preview', (s) => s.reply(404, null))
    ..onGet('/api/v1/manyfold/models/m2/preview', (s) => s.reply(404, null));

  Map<String, dynamic> file(String id, {bool importable = true, int? inLib}) =>
      {
        'id': id,
        'name': '$id.stl',
        'mime': importable ? 'model/stl' : 'application/pdf',
        'importable': importable,
        'library_file': inLib == null
            ? null
            : {'id': inLib, 'filename': '$id.stl', 'folder_id': 3},
      };

  void model(String id, List<Map<String, dynamic>> files) => server.onGet(
    '/api/v1/manyfold/models/$id',
    (s) => s.reply(200, {
      'id': id,
      'name': id == 'm1' ? 'Dragon' : 'Swatch box',
      'tags': const <String>[],
      'url': 'http://mf/models/$id',
      'has_preview': false,
      'files': files,
    }),
  );

  void import(String modelId, String fileId, {int status = 200}) =>
      server.onPost(
        '/api/v1/manyfold/import',
        (s) => s.reply(
          status,
          status == 200
              ? {
                  'library_file_id': 40,
                  'filename': '$fileId.stl',
                  'folder_id': 5,
                  'was_existing': false,
                }
              : {
                  'detail': {'code': 'manyfold_unreachable', 'message': 'x'},
                },
        ),
        data: {'model_id': modelId, 'file_id': fileId, 'folder_id': null},
      );

  Future<void> open(WidgetTester tester, {List<Override> extra = const []}) =>
      pumpPhone(
        tester,
        const ModelSourcesScreen(),
        overrides: [...overrides, ...extra],
      ).then((_) => tester.pumpAndSettle());

  group('the Manyfold tab', () {
    testWidgets('is absent on a server without the routes', (tester) async {
      status(404);
      await open(tester, extra: [currentUserOverride(user({}))]);
      expect(find.byType(TabBar), findsNothing);
      expect(find.text(l10n(tester).mwResolve), findsOneWidget);
    });

    testWidgets('is absent for a session refused manyfold:view', (
      tester,
    ) async {
      status(403, {'detail': 'Missing required permissions'});
      await open(tester, extra: [currentUserOverride(user({}))]);
      expect(find.byType(TabBar), findsNothing);
    });

    testWidgets('waits for a connection unless the user can make one', (
      tester,
    ) async {
      status(200, {'configured': false, 'url': ''});
      await open(tester, extra: [currentUserOverride(user({}))]);
      expect(find.byType(TabBar), findsNothing);
    });

    testWidgets('lists the models once connected', (tester) async {
      status(200, {'configured': true, 'url': 'http://mf'});
      listing();
      await open(tester, extra: [currentUserOverride(user({}))]);

      await tester.tap(find.text(l10n(tester).manyfoldTitle));
      await tester.pumpAndSettle();

      expect(find.text('Dragon'), findsOneWidget);
      expect(find.text(l10n(tester).mfModelCount(2)), findsOneWidget);
      // Ticking is for whoever may import.
      expect(find.byType(Checkbox), findsNothing);
    });
  });

  testWidgets('a search asks Manyfold once the typing pauses', (tester) async {
    status(200, {'configured': true, 'url': 'http://mf'});
    listing();
    server.onGet(
      '/api/v1/manyfold/models',
      (s) => s.reply(200, {
        'total': 0,
        'page': 1,
        'has_next': false,
        'has_previous': false,
        'models': <Object>[],
      }),
      queryParameters: {'q': 'gear', 'page': 1},
    );
    await open(tester, extra: [currentUserOverride(user({}))]);
    await tester.tap(find.text(l10n(tester).manyfoldTitle));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'gear');
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Dragon'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    expect(find.text(l10n(tester).mfNoModels), findsOneWidget);
  });

  testWidgets('ticked models import every printable file not in the library, '
      'one after another, and say how it went', (tester) async {
    status(200, {'configured': true, 'url': 'http://mf'});
    listing();
    model('m1', [file('a'), file('b', importable: false), file('c', inLib: 7)]);
    model('m2', [file('d')]);
    import('m1', 'a');
    import('m2', 'd', status: 502);
    await open(
      tester,
      extra: [
        currentUserOverride(user({Permissions.manyfoldImport})),
      ],
    );
    await tester.tap(find.text(l10n(tester).manyfoldTitle));
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n(tester).mfSelectPage));
    await tester.pumpAndSettle();
    expect(find.text(l10n(tester).mfModelsSelected(2)), findsOneWidget);

    await tester.tap(find.text(l10n(tester).mfImportModels));
    await tester.pumpAndSettle();

    expect(find.text(l10n(tester).mfBulkDone(1, 0, 1)), findsOneWidget);
    expect(find.text(l10n(tester).mfModelsSelected(2)), findsNothing);
    await tester.pumpAndSettle(const Duration(seconds: 5));
    expect(
      find.text(
        l10n(
          tester,
        ).mfBulkFailed('Swatch box: d.stl', l10n(tester).mfErrUnreachable),
      ),
      findsOneWidget,
    );
  });

  group('a model', () {
    Future<void> openModel(WidgetTester tester, Set<String> permissions) =>
        pumpPhone(
          tester,
          const ManyfoldModelScreen(modelId: 'm1', title: 'Dragon'),
          overrides: [...overrides, currentUserOverride(user(permissions))],
        ).then((_) => tester.pumpAndSettle());

    setUp(() {
      model('m1', [
        file('a'),
        file('b', importable: false),
        file('c', inLib: 7),
      ]);
      server.onGet(
        '/api/v1/manyfold/models/m1/preview',
        (s) => s.reply(404, null),
      );
    });

    testWidgets('shows each file state', (tester) async {
      await openModel(tester, {Permissions.manyfoldImport});

      expect(find.text(l10n(tester).mfNotImportable), findsOneWidget);
      expect(find.text(l10n(tester).mfInLibrary), findsOneWidget);
      expect(find.text(l10n(tester).mfShowInLibrary), findsOneWidget);
      expect(find.text(l10n(tester).mfImport), findsOneWidget);
      // Only "a" is still to import, and only it has a box beside "Select all".
      expect(find.byType(Checkbox), findsNWidgets(2));
    });

    testWidgets('imports one file and says so', (tester) async {
      import('m1', 'a');
      await openModel(tester, {Permissions.manyfoldImport});

      await tester.tap(find.text(l10n(tester).mfImport));
      await tester.pumpAndSettle();

      expect(find.text(l10n(tester).mfImported('a.stl')), findsOneWidget);
    });

    testWidgets('offers no import without manyfold:import', (tester) async {
      await openModel(tester, {});

      expect(find.text(l10n(tester).mfImport), findsNothing);
      expect(find.text(l10n(tester).mfImportTo), findsNothing);
      expect(find.byType(Checkbox), findsNothing);
    });
  });
}
