import 'dart:io';

import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/core/models/api_key.dart';
import 'package:bambuddy_mobile/core/models/manyfold.dart';
import 'package:bambuddy_mobile/data/api_keys_repository.dart';
import 'package:bambuddy_mobile/data/library_repository.dart';
import 'package:bambuddy_mobile/data/manyfold_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';

/// A Manyfold install the server under test can reach, with an OAuth
/// application holding "public read". Without the three variables only the
/// server's own answers are checked — the refusals, the codes and the
/// connection writes — and not browsing or importing.
String? get _manyfoldUrl =>
    Platform.environment['BAMBUDDY_CONTRACT_MANYFOLD_URL'];
String get _clientId =>
    Platform.environment['BAMBUDDY_CONTRACT_MANYFOLD_CLIENT_ID'] ?? '';
String get _clientSecret =>
    Platform.environment['BAMBUDDY_CONTRACT_MANYFOLD_CLIENT_SECRET'] ?? '';

/// Manyfold (#1471): browsing a self-hosted library and importing its files.
void main() {
  group('manyfold contract', skip: contractSkipReason, () {
    late Dio dio;
    late ManyfoldRepository repo;
    late bool hasManyfold;

    setUpAll(() async {
      dio = await authenticatedDio();
      repo = ManyfoldRepository(dio);
      hasManyfold = await repo.status() != null;
    });

    tearDownAll(() async {
      if (hasManyfold) await repo.deleteConfig();
    });

    Matcher failure(String code, int status) => isA<ManyfoldFailure>()
        .having((f) => f.code, 'code', code)
        .having((f) => f.statusCode, 'status', status);

    bool skipOld() {
      if (!hasManyfold) markTestSkipped('server predates Manyfold');
      return !hasManyfold;
    }

    test('an older server answers 404, which reads as no Manyfold', () async {
      if (hasManyfold) {
        markTestSkipped('server has Manyfold');
        return;
      }
      final res = await dio.get<dynamic>(
        Endpoints.manyfoldStatus,
        options: Options(validateStatus: (_) => true),
      );
      expect(res.statusCode, 404);
    });

    test('before a connection, browsing is a coded 409', () async {
      if (skipOld()) return;
      await repo.deleteConfig();

      expect((await repo.status())?.configured, isFalse);
      final config = await repo.config();
      expect(config.configured, isFalse);
      expect(config.hasClientSecret, isFalse);
      await expectLater(
        repo.models(),
        throwsA(failure('manyfold_not_configured', 409)),
      );
      await expectLater(
        repo.import(modelId: 'abc', fileId: 'def'),
        throwsA(failure('manyfold_not_configured', 409)),
      );
    });

    test(
      'a bad URL and a missing secret are refused before signing in',
      () async {
        if (skipOld()) return;
        await repo.deleteConfig();

        await expectLater(
          repo.testConfig(url: 'ftp://mf', clientId: 'x', clientSecret: 'y'),
          throwsA(failure('manyfold_bad_url', 400)),
        );
        await expectLater(
          repo.testConfig(url: 'http://mf.invalid', clientId: 'x'),
          throwsA(failure('manyfold_secret_required', 400)),
        );
        await expectLater(
          repo.saveConfig(url: 'http://mf.invalid', clientId: 'x'),
          throwsA(failure('manyfold_secret_required', 400)),
        );
      },
    );

    test('a stored connection keeps its secret and can be dropped', () async {
      if (skipOld()) return;
      final saved = await repo.saveConfig(
        url: 'http://127.0.0.1:9/',
        clientId: 'contract',
        clientSecret: 'secret',
      );
      expect(saved.configured, isTrue);
      expect(saved.hasClientSecret, isTrue);
      // The server strips the trailing slash.
      expect(saved.url, 'http://127.0.0.1:9');

      // An empty secret keeps the stored one.
      final again = await repo.saveConfig(
        url: 'http://127.0.0.1:9',
        clientId: 'contract2',
      );
      expect(again.clientId, 'contract2');
      expect(again.hasClientSecret, isTrue);
      expect((await repo.status())?.url, 'http://127.0.0.1:9');

      // Nothing listens there: a Manyfold failure, never Bambuddy's own 401/403.
      await expectLater(repo.models(), throwsA(isA<ManyfoldFailure>()));

      await repo.deleteConfig();
      expect((await repo.status())?.configured, isFalse);
    });

    test(
      'browsing is not connecting: a viewer and an API key may only look',
      () async {
        if (skipOld()) return;
        final viewer = await contractUser(dio, ['manyfold:view']);
        final asViewer = ManyfoldRepository(viewer.dio);
        expect(await asViewer.status(), isNotNull);
        await expectLater(
          asViewer.saveConfig(url: 'http://mf.invalid', clientId: 'x'),
          throwsA(isA<AuthException>()),
        );
        await expectLater(
          asViewer.import(modelId: 'abc', fileId: 'def'),
          throwsA(isA<AuthException>()),
        );

        final nobody = await contractUser(dio, ['printers:read']);
        expect(await ManyfoldRepository(nobody.dio).status(), isNull);

        final keys = ApiKeysRepository(dio);
        final key = await keys.create(
          ApiKeyCreateInput(
            name: 'contract manyfold',
            scopes: {ApiKeyScope.readStatus},
          ),
        );
        addTearDown(
          () => dio.delete<dynamic>(
            Endpoints.apiKeyById(key.apiKey.id),
            options: Options(validateStatus: (_) => true),
          ),
        );
        await pollUntil(
          'key ${key.apiKey.id} to be committed',
          () async => (await keys.list()).any((k) => k.id == key.apiKey.id)
              ? true
              : null,
          within: const Duration(seconds: 10),
          every: const Duration(milliseconds: 100),
        );
        final asKey = ManyfoldRepository(
          Dio(BaseOptions(baseUrl: contractBaseUrl))
            ..options.headers['X-API-Key'] = key.key,
        );
        expect(await asKey.status(), isNotNull);
        await expectLater(
          asKey.saveConfig(url: 'http://mf.invalid', clientId: 'x'),
          throwsA(isA<AuthException>()),
        );
      },
    );

    group('against a real Manyfold', () {
      String? skip() {
        if (!hasManyfold) return 'server predates Manyfold';
        if ((_manyfoldUrl ?? '').isEmpty) {
          return 'BAMBUDDY_CONTRACT_MANYFOLD_URL is unset';
        }
        return null;
      }

      setUp(() async {
        if (skip() != null) return;
        await repo.saveConfig(
          url: _manyfoldUrl!,
          clientId: _clientId,
          clientSecret: _clientSecret,
        );
      });

      test('browses, imports once and points at the library file', () async {
        if (skip() case final reason?) {
          markTestSkipped(reason);
          return;
        }
        expect(
          await repo.testConfig(url: _manyfoldUrl!, clientId: _clientId),
          greaterThan(0),
        );
        final page = await repo.models();
        expect(page.page, 1);
        expect(page.models, isNotEmpty);
        expect(page.total, greaterThanOrEqualTo(page.models.length));

        final model = await repo.model(page.models.first.id);
        expect(model.url, startsWith(_manyfoldUrl!));
        final printable = model.files.firstWhere((f) => f.importable);
        expect(printable.typeLabel, isNot('?'));
        // A model without a preview is null, not an error.
        if (!model.hasPreview) expect(await repo.preview(model.id), isNull);

        final first = await repo.import(
          modelId: model.id,
          fileId: printable.id,
        );
        addTearDown(
          () => LibraryRepository(dio).deleteFile(first.libraryFileId),
        );
        final second = await repo.import(
          modelId: model.id,
          fileId: printable.id,
        );
        expect(second.wasExisting, isTrue);
        expect(second.libraryFileId, first.libraryFileId);

        final after = await repo.model(model.id);
        final ref = after.files.firstWhere((f) => f.id == printable.id);
        expect(ref.libraryFile?.id, first.libraryFileId);
        expect(ref.libraryFile?.folderId, first.folderId);
        expect(
          after.importCandidates.map((f) => f.id),
          isNot(contains(printable.id)),
        );

        final other = model.files.where((f) => !f.importable).firstOrNull;
        if (other != null) {
          await expectLater(
            repo.import(modelId: model.id, fileId: other.id),
            throwsA(failure('manyfold_not_importable', 400)),
          );
        }
      });

      test(
        'a search narrows the listing and an unknown model is a coded 404',
        () async {
          if (skip() case final reason?) {
            markTestSkipped(reason);
            return;
          }
          final none = await repo.models(query: 'zz-no-such-model-zz');
          expect(none.models, isEmpty);
          expect(none.total, 0);
          await expectLater(
            repo.model('nosuchmodel'),
            throwsA(failure('manyfold_not_found', 404)),
          );
        },
      );
    });
  });
}
