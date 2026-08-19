import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/filament_requirement.dart';
import 'package:bambuddy_mobile/core/models/slicer_preset.dart';
import 'package:bambuddy_mobile/data/slicer_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late SlicerRepository repo;

  const preset = SlicerPreset(source: 'local', id: '12', name: '0.20 mm');

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://s.local:8000'));
    adapter = DioAdapter(dio: dio);
    repo = SlicerRepository(dio);
  });

  group('presetValues', () {
    test('parses resolved values and turns override support on', () async {
      adapter.onGet(
        '/api/v1/slicer/preset-values',
        (s) => s.reply(200, {
          'resolved': true,
          'values': {'layer_height': '0.2', 'wall_loops': 3},
          'reason': 'ok',
        }),
        queryParameters: {'source': 'local', 'id': '12', 'slot': 'process'},
      );

      final values = await repo.presetValues(preset);

      expect(values!.resolved, isTrue);
      expect(values.values['layer_height'], '0.2');
      expect(values.cause, PresetValuesCause.ok);
      expect(await repo.supportsProcessOverrides(), isTrue);
    });

    test('404 → null, support off (server < 1.2.6)', () async {
      adapter.onGet(
        '/api/v1/slicer/preset-values',
        (s) => s.reply(404, {'detail': 'Not Found'}),
        queryParameters: {'source': 'local', 'id': '12', 'slot': 'process'},
      );

      expect(await repo.presetValues(preset), isNull);
      expect(await repo.supportsProcessOverrides(), isFalse);
    });

    test('resolved:false is NOT missing support — the route answered', () async {
      // Unreadable values and a missing route are different things: the first
      // leaves the panel open on schema defaults, the second hides it entirely.
      // The usual cause is a sidecar older than the endpoint.
      adapter.onGet(
        '/api/v1/slicer/preset-values',
        (s) => s.reply(200, {
          'resolved': false,
          'values': <String, dynamic>{},
          'reason': 'sidecar_outdated',
        }),
        queryParameters: {'source': 'local', 'id': '12', 'slot': 'process'},
      );

      final values = await repo.presetValues(preset);

      expect(values!.resolved, isFalse);
      expect(values.cause, PresetValuesCause.sidecarOutdated);
      expect(await repo.supportsProcessOverrides(), isTrue);
    });

    test('any other failure degrades to unresolved rather than throwing', () async {
      adapter.onGet(
        '/api/v1/slicer/preset-values',
        (s) => s.reply(500, {'detail': 'boom'}),
        queryParameters: {'source': 'local', 'id': '12', 'slot': 'process'},
      );

      final values = await repo.presetValues(preset);

      expect(values, isNotNull);
      expect(values!.resolved, isFalse);
    });

    test('an expired session throws instead of degrading', () async {
      // The one failure that must not be absorbed: swallowed here, nothing
      // redirects to the login and the panel just sits there empty.
      adapter.onGet(
        '/api/v1/slicer/preset-values',
        (s) => s.reply(401, {'detail': 'Not authenticated'}),
        queryParameters: {'source': 'local', 'id': '12', 'slot': 'process'},
      );

      await expectLater(
        repo.presetValues(preset),
        throwsA(isA<AuthException>()
            .having((e) => e.code, 'code', AppErrorCode.unauthorized)),
      );
      expect(repo.supportsProcessOverrides(), completion(isFalse),
          reason: 'a rejected call proves nothing about the route');
    });

    test('a refusal hides the panel without throwing', () async {
      // 403 maps to AuthException like a 401 does, but it means something else
      // entirely: this caller lacks `library:upload`, permanently. Throwing it
      // out of a panel read would put a dialog in front of a control the user
      // cannot have — and the slice needs the same permission anyway.
      adapter.onGet(
        '/api/v1/slicer/preset-values',
        (s) => s.reply(403, {'detail': "API key does not have 'library:upload'"}),
        queryParameters: {'source': 'local', 'id': '12', 'slot': 'process'},
      );

      expect(await repo.presetValues(preset), isNull);
      expect(await repo.supportsProcessOverrides(), isFalse);
    });

    test('a refusal is not recorded as an answer about the route', () async {
      // The distinction that matters: a 403 says nothing about whether the
      // server has the route, so it must not latch the observation that
      // outranks the version. A caller who gains the permission gets the panel.
      final dio = Dio(BaseOptions(baseUrl: 'http://s.local:8000'));
      final repo = SlicerRepository(dio);
      const query = {'source': 'local', 'id': '12', 'slot': 'process'};

      // A second DioAdapter replaces the first on the same Dio, which is how the
      // one repository instance gets to see two different answers.
      DioAdapter(dio: dio).onGet(
        '/api/v1/slicer/preset-values',
        (s) => s.reply(403, {'detail': 'nope'}),
        queryParameters: query,
      );

      expect(await repo.presetValues(preset), isNull);
      expect(await repo.supportsProcessOverrides(), isFalse);

      DioAdapter(dio: dio).onGet(
        '/api/v1/slicer/preset-values',
        (s) => s.reply(200, {'resolved': true, 'values': {}, 'reason': 'ok'}),
        queryParameters: query,
      );

      expect(await repo.presetValues(preset), isNotNull);
      expect(await repo.supportsProcessOverrides(), isTrue,
          reason: 'the refusal was about the caller, not the server');
    });

    test('a 400 from a bad slot is not read as the route being absent', () async {
      // Only `slot=process` is supported and anything else is a 400
      // (routes/slicer_presets.py). We always send `process`, but a 400 must
      // never latch "no such route" — that would hide the panel for the session
      // on a server that has it.
      adapter.onGet(
        '/api/v1/slicer/preset-values',
        (s) => s.reply(400, {'detail': "Only the 'process' slot is supported"}),
        queryParameters: {'source': 'local', 'id': '12', 'slot': 'process'},
      );

      final values = await repo.presetValues(preset);
      expect(values, isNotNull, reason: 'degrades to unresolved, not to null');
      expect(values!.resolved, isFalse);
      expect(await repo.supportsProcessOverrides(), isFalse,
          reason: 'no version and no observation — the older contract');
    });
  });

  group('filamentRequirements', () {
    const path = '/api/v1/library/files/9/filament-requirements';

    test('names the plate, or used_in_plate can never discriminate', () async {
      // For a file that was never sliced the server decides used-vs-unused by
      // running a preview slice, and it only does that when a plate is named.
      // Without plate_id it flags every slot used and the marking is dead code.
      // 1 matches what the slice itself does: SliceRequest.plate left null is
      // plate 1 on the sidecar. The mock answers only this exact query, so a
      // missing or different plate_id fails the call rather than passing quietly.
      adapter.onGet(
        path,
        (s) => s.reply(200, {
          'filaments': [
            {'slot_id': 1, 'used_in_plate': true},
            {'slot_id': 2, 'used_in_plate': false},
          ],
        }),
        queryParameters: {'full_slots': true, 'plate_id': 1},
      );
      expect(anyUnused(await repo.filamentRequirements(id: 9, isArchive: false)),
          isTrue);
    });

    test('asks for every project slot, not only the used ones', () async {
      // `filament_presets` is positional, so a used-only list binds the user's
      // pick to the wrong slot (server #2712). full_slots is what the server
      // itself says the slice modal must send.
      adapter.onGet(
        path,
        (s) => s.reply(200, {
          'filaments': [
            {'slot_id': 1, 'type': 'PLA', 'color': '#FF0000', 'used_in_plate': false},
            {'slot_id': 2, 'type': 'PETG', 'color': '#00FF00', 'used_in_plate': true},
          ],
        }),
        queryParameters: {'full_slots': true, 'plate_id': 1},
      );

      final reqs = await repo.filamentRequirements(id: 9, isArchive: false);
      expect(reqs, hasLength(2));
      expect(reqs[0].usedInPlate, isFalse);
      expect(reqs[1].usedInPlate, isTrue);
      expect(anyUnused(reqs), isTrue);
    });

    test('a row without the flag counts as used', () async {
      // Absent means "cannot tell", and used keeps the slot offered rather than
      // implying the plate ignores it.
      adapter.onGet(
        path,
        (s) => s.reply(200, {
          'filaments': [
            {'slot_id': 1, 'type': 'PLA'},
          ],
        }),
        queryParameters: {'full_slots': true, 'plate_id': 1},
      );

      final reqs = await repo.filamentRequirements(id: 9, isArchive: false);
      expect(reqs.single.usedInPlate, isTrue);
      expect(anyUnused(reqs), isFalse,
          reason: 'nothing was discriminated, so nothing may be marked');
    });

    test('all-used is not a discrimination — the server falls back to it', () {
      // When its preview slice yields nothing the server flags every slot used,
      // so all-true is indistinguishable from "could not tell".
      const all = [
        FilamentRequirement(slotId: 1, usedInPlate: true),
        FilamentRequirement(slotId: 2, usedInPlate: true),
      ];
      expect(anyUnused(all), isFalse);
    });

    test('a failure degrades to no slots rather than throwing', () async {
      adapter.onGet(
        path,
        (s) => s.reply(500, {'detail': 'boom'}),
        queryParameters: {'full_slots': true, 'plate_id': 1},
      );
      expect(await repo.filamentRequirements(id: 9, isArchive: false), isEmpty);
    });
  });

  group('embeddedSettings', () {
    test('reads the design from a library file', () async {
      adapter.onGet(
        '/api/v1/library/files/9/plates',
        (s) => s.reply(200, {
          'file_id': 9,
          'plates': [],
          'embedded_printer': 'Bambu Lab X2D 0.4 nozzle',
          'embedded_process': '0.20mm Standard @BBL X2D',
          'design_overrides': [
            {'key': 'wall_loops', 'value': '4', 'printer_coupled': false},
          ],
        }),
      );

      final settings = await repo.embeddedSettings(id: 9, isArchive: false);
      expect(settings.printer, 'Bambu Lab X2D 0.4 nozzle');
      expect(settings.serverSupportsAsDesigned, isTrue);
    });

    test('reads an archive from the archive route', () async {
      adapter.onGet(
        '/api/v1/archives/9/plates',
        (s) => s.reply(200, {
          'archive_id': 9,
          'plates': [],
          'embedded_printer': 'Bambu Lab X2D 0.6 nozzle',
          'embedded_process': '0.30mm Standard @BBL X2D 0.6 nozzle',
          'design_overrides': [],
        }),
      );

      final settings = await repo.embeddedSettings(id: 9, isArchive: true);
      expect(settings.printer, 'Bambu Lab X2D 0.6 nozzle');
      expect(settings.isAvailable, isTrue,
          reason: 'an empty override list is still a server that has the key');
    });

    test('an older server naming the printer still offers nothing', () async {
      // embedded_printer predates use_embedded_settings by half a year and the
      // version cannot separate them — every 1.2.6 daily reports `1.2.6b1`. The
      // missing design_overrides key is the whole signal.
      adapter.onGet(
        '/api/v1/library/files/9/plates',
        (s) => s.reply(200, {
          'file_id': 9,
          'plates': [],
          'embedded_printer': 'Bambu Lab X2D 0.4 nozzle',
          'embedded_process': '0.20mm Standard @BBL X2D',
        }),
      );

      final settings = await repo.embeddedSettings(id: 9, isArchive: false);
      expect(settings.printer, isNotNull);
      expect(settings.isAvailable, isFalse);
    });

    test('a failure degrades to none rather than throwing', () async {
      // The switch is a nicety on top of a form that works without it; an
      // unreadable 3MF must not take the slice screen down with it.
      adapter.onGet(
        '/api/v1/library/files/9/plates',
        (s) => s.reply(500, {'detail': 'boom'}),
      );

      final settings = await repo.embeddedSettings(id: 9, isArchive: false);
      expect(settings.isAvailable, isFalse);
    });

    test('a 404 is the answer for a route that is not there', () async {
      adapter.onGet(
        '/api/v1/library/files/9/plates',
        (s) => s.reply(404, {'detail': 'Not Found'}),
      );

      expect((await repo.embeddedSettings(id: 9, isArchive: false)).isAvailable,
          isFalse);
    });
  });
}
