import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/core/settings/server_settings.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';

/// The server half of what `test/core/settings/server_settings_test.dart`
/// assumes.
///
/// That suite proves the app copes with a settings map shaped a particular way.
/// It cannot prove bambuddy still produces that shape, because the map it reads
/// is one we wrote. Everything here is the other side of the same statements —
/// and each one is a rule the app already depends on somewhere, not a curiosity.
///
/// These tests WRITE settings. That is safe only because the workflow gives
/// every run a container created seconds earlier and destroyed with the job;
/// never point BAMBUDDY_CONTRACT_URL at a server anyone relies on.
void main() {
  group('settings contract', skip: contractSkipReason, () {
    late Dio dio;
    String? originalSnippets;

    setUpAll(() async {
      dio = await authenticatedDio();
      final res = await dio.get<Map<String, dynamic>>(Endpoints.appSettings);
      originalSnippets = res.data?['gcode_snippets'] as String?;
    });

    tearDownAll(() async {
      if (originalSnippets != null) {
        await dio.put<dynamic>(
          Endpoints.appSettingsUpdate,
          data: {'gcode_snippets': originalSnippets},
        );
      }
    });

    test('the trailing slash on the write route is load-bearing', () async {
      // Two constants for one resource looks like an oversight until this runs:
      // FastAPI serves the write at the slashed path only, and the unslashed
      // one is not a redirect that Dio would follow — it is a refusal.
      expect(Endpoints.appSettingsUpdate, '${Endpoints.appSettings}/');

      final unslashed = await dio.put<dynamic>(
        Endpoints.appSettings,
        data: {'auto_archive': true},
        options: Options(validateStatus: (_) => true),
      );
      expect(
        unslashed.statusCode,
        405,
        reason:
            'PUT ${Endpoints.appSettings} answered ${unslashed.statusCode}; if '
            'the server started accepting it, the two constants could collapse '
            'into one — but until then dropping the slash silently stops saving',
      );

      final slashed = await dio.put<Map<String, dynamic>>(
        Endpoints.appSettingsUpdate,
        data: {'auto_archive': true},
      );
      expect(slashed.statusCode, 200);
    });

    test('an unknown key is accepted and then silently dropped', () async {
      // This is load-bearing in a way that is easy to miss: the app decides
      // whether a server supports a setting by whether the key comes back from
      // GET. That gate only means anything while an unknown key is accepted
      // without complaint and left out of the response. A server that started
      // rejecting unknown keys, or echoing them back, would change the answer
      // to "supported" for every setting the app can name.
      const probe = 'contract_probe_key_that_should_not_exist';

      final put = await dio.put<dynamic>(
        Endpoints.appSettingsUpdate,
        data: {probe: 42},
        options: Options(validateStatus: (_) => true),
      );
      expect(
        put.statusCode,
        200,
        reason:
            'the server refused an unknown key, so absence-from-GET is no '
            'longer a usable capability gate',
      );

      final get = await dio.get<Map<String, dynamic>>(Endpoints.appSettings);
      expect(
        get.data!.containsKey(probe),
        isFalse,
        reason:
            'the server echoed an unknown key back; absence-from-GET would '
            'then report every nameable setting as supported',
      );
    });

    test('a blob field arrives as JSON inside a string', () async {
      // decodeSettingBlob has two branches — string and object — and its comment
      // says the object one is there in case a future server types these fields
      // properly. This pins which branch is the live one today, so that change
      // arrives as a failing test rather than as configuration quietly lost.
      const snippets = '{"X1C":[{"name":"Contract probe","gcode":"G28"}]}';

      await dio.put<dynamic>(
        Endpoints.appSettingsUpdate,
        data: {'gcode_snippets': snippets},
      );
      final get = await dio.get<Map<String, dynamic>>(Endpoints.appSettings);

      expect(
        get.data!['gcode_snippets'],
        isA<String>(),
        reason:
            'no longer a string — decodeSettingBlob\'s object branch is now '
            'the live path, and every caller should be re-read against it',
      );

      final decoded = get.data!.settingBlob('gcode_snippets');
      expect(decoded, isNotNull);
      expect(decoded!.keys, contains('X1C'));
    });

    test('the server parses the blob rather than storing it whole', () async {
      // A well-formed JSON array is still refused: the field is specified as an
      // object keyed by printer model. Worth pinning because it tells us the
      // validation lives server-side — the app cannot write a blob shape the
      // server has not agreed to, whatever it manages to serialise.
      final res = await dio.put<dynamic>(
        Endpoints.appSettingsUpdate,
        data: {'gcode_snippets': '[{"name":"Home","gcode":"G28"}]'},
        options: Options(validateStatus: (_) => true),
      );

      expect(
        res.statusCode,
        422,
        reason:
            'a JSON array was accepted where an object keyed by printer model '
            'is specified; the server may have stopped validating this field',
      );
    });
  });
}
