import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/library_tag.dart';
import 'package:bambuddy_mobile/data/library_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late LibraryRepository repo;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://s.local:8000'));
    adapter = DioAdapter(dio: dio);
    repo = LibraryRepository(dio);
  });

  group('listTags', () {
    test('parsuje katalog, pomija niepoprawny wpis', () async {
      adapter.onGet(
        '/api/v1/library/tags',
        (s) => s.reply(200, [
          {'id': 1, 'name': 'zabawki', 'file_count': 3},
          'śmieć',
          {'id': 2, 'name': 'petg'}, // brak file_count → 0
        ]),
      );

      final tags = await repo.listTags();

      expect(tags, hasLength(2));
      expect(tags!.first.name, 'zabawki');
      expect(tags.first.fileCount, 3);
      expect(tags.last.fileCount, 0);
    });

    test('404 → null (serwer bez katalogu tagów)', () async {
      adapter.onGet(
        '/api/v1/library/tags',
        (s) => s.reply(404, {'detail': 'Not Found'}),
      );

      expect(await repo.listTags(), isNull);
    });

    test('500 to błąd, nie brak funkcji', () async {
      adapter.onGet(
        '/api/v1/library/tags',
        (s) => s.reply(500, {'detail': 'boom'}),
      );

      expect(repo.listTags(), throwsA(isA<AppApiException>()));
    });

    test('401 wypływa jako AuthException', () async {
      adapter.onGet(
        '/api/v1/library/tags',
        (s) => s.reply(401, {'detail': 'nope'}),
      );

      expect(
        repo.listTags(),
        throwsA(isA<AuthException>()
            .having((e) => e.code, 'code', AppErrorCode.unauthorized)),
      );
    });
  });

  test('createTag: 409 zachowuje status, by UI powiedział „już istnieje"',
      () async {
    adapter.onPost(
      '/api/v1/library/tags',
      (s) => s.reply(409, {'detail': 'Tag with this name already exists'}),
      data: {'name': 'zabawki'},
    );

    expect(
      repo.createTag('zabawki'),
      throwsA(isA<AppApiException>().having((e) => e.statusCode, 'status', 409)),
    );
  });

  test('createTag: zwraca utworzony tag', () async {
    adapter.onPost(
      '/api/v1/library/tags',
      (s) => s.reply(201, {'id': 7, 'name': 'petg', 'file_count': 0}),
      data: {'name': 'petg'},
    );

    final tag = await repo.createTag('petg');

    expect(tag.id, 7);
    expect(tag.name, 'petg');
  });

  test('listFilesByTags: wysyła powtórzone tag_ids i parsuje tagi pliku',
      () async {
    adapter.onGet(
      '/api/v1/library/files',
      (s) => s.reply(200, [
        {
          'id': 11,
          'filename': 'kubek.3mf',
          'file_type': '3mf',
          'file_size': 1024,
          'print_count': 0,
          'tags': [
            {'id': 1, 'name': 'zabawki'},
            'śmieć',
          ],
        },
      ]),
      queryParameters: {'tag_ids': [1, 2]},
    );

    final files = await repo.listFilesByTags([1, 2]);

    expect(files, hasLength(1));
    expect(files.first.tagNames, ['zabawki']);
  });

  // Kształt URL, nie tylko mapa parametrów: FastAPI czyta `tag_ids` jako listę
  // z POWTÓRZONEGO klucza. Gdyby Dio zserializował go jako `tag_ids[]=` albo
  // `tag_ids=1,2`, serwer zobaczyłby zero tagów i cicho oddał całą bibliotekę —
  // filtr wyglądałby na zepsuty dopiero na ekranie.
  test('listFilesByTags: tag_ids lecą jako powtórzony klucz', () async {
    String? query;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      query = options.uri.query;
      handler.next(options);
    }));
    adapter.onGet(
      '/api/v1/library/files',
      (s) => s.reply(200, <dynamic>[]),
      queryParameters: {'tag_ids': [1, 2]},
    );

    await repo.listFilesByTags([1, 2]);

    expect(query, 'tag_ids=1&tag_ids=2');
  });

  test('listFiles: brak tagów w odpowiedzi → pusta lista, nie null', () async {
    adapter.onGet(
      '/api/v1/library/files',
      (s) => s.reply(200, [
        {
          'id': 12,
          'filename': 'stary.gcode',
          'file_type': 'gcode',
          'file_size': 10,
          'print_count': 1,
        },
      ]),
      queryParameters: {'include_root': true},
    );

    final files = await repo.listFiles();

    expect(files.single.tags, isEmpty);
  });

  test('assignTags: wysyła akcję po nazwie z kontraktu i czyta liczniki',
      () async {
    adapter.onPost(
      '/api/v1/library/tags/bulk-assign',
      (s) => s.reply(200, {
        'files_updated': 2,
        'associations_added': 0,
        'associations_removed': 4,
      }),
      data: {
        'file_ids': [11, 12],
        'tag_ids': <int>[],
        'action': 'replace',
      },
    );

    final result = await repo.assignTags(
      fileIds: [11, 12],
      tagIds: const [],
      action: TagAssignAction.replace,
    );

    expect(result.filesUpdated, 2);
    expect(result.removed, 4);
    expect(result.added, 0);
  });

  test('assignTags: mniej plików niż wysłano = częściowe zastosowanie',
      () async {
    adapter.onPost(
      '/api/v1/library/tags/bulk-assign',
      (s) => s.reply(200, {'files_updated': 1}), // reszta pól nieobecna → 0
      data: {
        'file_ids': [11, 12],
        'tag_ids': [1],
        'action': 'add',
      },
    );

    final result = await repo.assignTags(
      fileIds: [11, 12],
      tagIds: const [1],
      action: TagAssignAction.add,
    );

    expect(result.filesUpdated, 1);
    expect(result.added, 0);
  });

  group('cross-model variants (#671)', () {
    /// One listing row in the 1.2.6 shape — variant fields present.
    Map<String, dynamic> row126({int variantCount = 0, int? groupId}) => {
          'id': 7,
          'filename': 'mug.3mf',
          'file_type': '3mf',
          'file_size': 1024,
          'print_count': 0,
          'variant_group_id': groupId,
          'variant_count': variantCount,
        };

    /// The same row before 1.2.6 — the variant keys are absent entirely.
    Map<String, dynamic> row125() => {
          'id': 7,
          'filename': 'mug.3mf',
          'file_type': '3mf',
          'file_size': 1024,
          'print_count': 0,
        };

    test('variant_count present in the listing turns support on', () async {
      adapter.onGet(
        '/api/v1/library/files',
        (s) => s.reply(200, [row126(variantCount: 2, groupId: 3)]),
        queryParameters: {'include_root': true},
      );

      await repo.listFiles();

      expect(await repo.supportsCrossModelVariants(), isTrue);
    });

    test('variant_count absent from the listing turns support off', () async {
      adapter.onGet(
        '/api/v1/library/files',
        (s) => s.reply(200, [row125()]),
        queryParameters: {'include_root': true},
      );

      await repo.listFiles();

      expect(await repo.supportsCrossModelVariants(), isFalse);
    });

    test('an empty listing settles nothing — the cautious no stands',
        () async {
      // A library with no files says nothing about the server generation, so
      // the observation must stay undecided rather than record "unsupported".
      adapter.onGet(
        '/api/v1/library/files',
        (s) => s.reply(200, <dynamic>[]),
        queryParameters: {'include_root': true},
      );

      await repo.listFiles();

      // With no ServerVersionService the fallback is false — what matters is
      // that an empty list did not pin the answer.
      expect(await repo.supportsCrossModelVariants(), isFalse);
    });

    test('parses a file group', () async {
      adapter.onGet(
        '/api/v1/library/variant-groups/by-file/7',
        (s) => s.reply(200, {
          'id': 3,
          'name': 'Mug',
          'members': [
            {
              'library_file_id': 7,
              'filename': 'mug_h2c.3mf',
              'target_model': 'H2C',
              'position': 0,
            },
            {
              'library_file_id': 8,
              'filename': 'mug_h2s.3mf',
              'target_model': 'H2S',
              'position': 1,
            },
          ],
        }),
      );

      final group = await repo.variantGroupForFile(7);

      expect(group, isNotNull);
      expect(group!.targetModels, ['H2C', 'H2S']);
    });

    test('404 → null: an ungrouped file and an old server read the same',
        () async {
      adapter.onGet(
        '/api/v1/library/variant-groups/by-file/7',
        (s) => s.reply(404, {'detail': 'File is not part of a variant group'}),
      );

      expect(await repo.variantGroupForFile(7), isNull);
    });

    test('createVariantGroup sends members in priority order', () async {
      adapter.onPost(
        '/api/v1/library/variant-groups',
        (s) => s.reply(201, {'id': 3, 'name': 'Mug', 'members': <dynamic>[]}),
        data: {
          'members': [
            {'library_file_id': 7},
            {'library_file_id': 8},
          ],
        },
      );

      final group = await repo.createVariantGroup([7, 8]);

      expect(group.id, 3);
    });
  });

  // The library twin of `ArchiveRepository.plates` — same payload shape, so one
  // model reads both. This is also where the slice screen's "as designed" gate
  // gets its answer now, instead of from a second request to the same route.
  group('plates', () {
    test('reads plates and design presets off the library route', () async {
      adapter.onGet(
        '/api/v1/library/files/9/plates',
        (s) => s.reply(200, {
          'file_id': 9,
          'plates': [
            {'index': 1, 'name': 'Left', 'has_thumbnail': false},
            {'index': 2, 'name': 'Right', 'has_thumbnail': false},
          ],
          'is_multi_plate': true,
          'embedded_printer': 'Bambu Lab X2D 0.4 nozzle',
          'embedded_process': '0.20mm Standard @BBL X2D',
          'design_overrides': [
            {'key': 'wall_loops', 'value': '4', 'printer_coupled': false},
          ],
        }),
      );

      final plates = await repo.plates(9);

      expect(plates.plates.map((p) => p.index), [1, 2]);
      expect(plates.isMultiPlate, isTrue);
      expect(plates.embedded.printer, 'Bambu Lab X2D 0.4 nozzle');
      expect(plates.embedded.serverSupportsAsDesigned, isTrue);
      expect(plates.hasGcode, isFalse,
          reason: 'the library route does not answer has_gcode at all');
    });

    // The picker and the "as designed" switch are both niceties on top of a
    // form that works without them; an unreadable 3MF must not take the screen
    // down with it, and neither must a route that is not there.
    test('a failure and a missing route both leave nothing to offer', () async {
      adapter
        ..onGet('/api/v1/library/files/9/plates',
            (s) => s.reply(500, {'detail': 'boom'}))
        ..onGet('/api/v1/library/files/8/plates',
            (s) => s.reply(404, {'detail': 'Not Found'}));

      expect((await repo.plates(9)).embedded.isAvailable, isFalse);
      expect((await repo.plates(8)).plates, isEmpty);
    });
  });
}
