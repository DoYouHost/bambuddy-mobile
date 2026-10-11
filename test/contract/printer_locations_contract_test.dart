import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/core/api/server_version_service.dart';
import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_location.dart';
import 'package:bambuddy_mobile/data/printer_locations_repository.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';

/// Printer locations (server #2962): the managed list, the three writes, and —
/// on a server without them — that the app is told so by the answers
/// themselves rather than by a version number.
void main() {
  group('printer locations contract', skip: contractSkipReason, () {
    late Dio dio;
    late PrinterLocationsRepository locations;
    late PrintersRepository printers;
    late bool hasLocations;
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final names = <String>[];

    /// The seeded printer, and where it was filed before this file touched it.
    late Printer printer;

    setUpAll(() async {
      dio = await authenticatedDio();
      locations = PrinterLocationsRepository(dio, ServerVersionService(dio));
      printers = PrintersRepository(dio);
      printer = (await printers.fetchPrinters()).first;
      final probe = await dio.get<dynamic>(
        Endpoints.printerLocations,
        options: Options(validateStatus: (_) => true),
      );
      hasLocations = probe.statusCode == 200;
    });

    tearDownAll(() async {
      if (!hasLocations) return;
      await locations.assign([printer.id], printer.location);
      if (names.isNotEmpty) await locations.delete(names);
    });

    Future<PrinterLocation> create(String name, {String? icon, String? color}) {
      names.add(name);
      return locations.create(
        PrinterLocationDraft(name: name, icon: icon, color: color),
      );
    }

    Future<Printer> reread() async =>
        (await printers.fetchPrinters()).firstWhere((p) => p.id == printer.id);

    test('an older server is recognised from its own answers', () async {
      if (hasLocations) {
        markTestSkipped('server has printer locations');
        return;
      }
      expect(await locations.list(), isEmpty);
      expect(locations.capability.observedAnswer, isFalse);
    });

    test(
      'an empty location is listed with its style and no printers',
      () async {
        if (!hasLocations) {
          markTestSkipped('server predates printer locations');
          return;
        }
        final made = await create(
          'Loc-$stamp-a',
          icon: 'wrench',
          color: '#22c55e',
        );
        expect(made.id, isNotNull);
        expect(made.printerCount, 0);

        final listed = (await locations.list()).firstWhere(
          (l) => l.name == made.name,
        );
        expect(listed.icon, 'wrench');
        expect(listed.color, '#22c55e');
        expect(locations.capability.observedAnswer, isTrue);
      },
    );

    test(
      'a case variant of a name is a 409, on create and on rename',
      () async {
        if (!hasLocations) {
          markTestSkipped('server predates printer locations');
          return;
        }
        final a = await create('Loc-$stamp-case');
        await expectLater(
          locations.create(PrinterLocationDraft(name: a.name.toUpperCase())),
          throwsA(
            isA<AppApiException>().having((e) => e.statusCode, 'status', 409),
          ),
        );
        final other = await create('Loc-$stamp-other');
        await expectLater(
          locations.update(
            PrinterLocationDraft(
              name: other.name,
              newName: a.name.toLowerCase(),
            ),
          ),
          throwsA(
            isA<AppApiException>().having((e) => e.statusCode, 'status', 409),
          ),
        );
      },
    );

    test('assigning files a printer and counts it; a rename follows it and '
        'null takes it out', () async {
      if (!hasLocations) {
        markTestSkipped('server predates printer locations');
        return;
      }
      final home = 'Loc-$stamp-home';
      await create(home, icon: 'home');

      expect(await locations.assign([printer.id], home), 1);
      expect((await reread()).location, home);
      expect(
        (await locations.list()).firstWhere((l) => l.name == home).printerCount,
        1,
      );

      // The rename moves the printer in the same transaction, and a field that
      // is not sent keeps its value only when it is sent back — the app always
      // sends both, so an emptied icon is cleared.
      final renamed = '$home-renamed';
      names.add(renamed);
      final saved = await locations.update(
        PrinterLocationDraft(name: home, newName: renamed, color: '#3b82f6'),
      );
      expect(saved.name, renamed);
      expect(saved.icon, isNull);
      expect(saved.color, '#3b82f6');
      expect(saved.printerCount, 1);
      expect((await reread()).location, renamed);

      expect(await locations.assign([printer.id], null), 1);
      expect((await reread()).location, isNull);
    });

    test('a printer that does not exist is a 404 and moves nothing', () async {
      if (!hasLocations) {
        markTestSkipped('server predates printer locations');
        return;
      }
      await expectLater(
        locations.assign([printer.id, 999999], 'Loc-$stamp-never'),
        throwsA(
          isA<AppApiException>().having((e) => e.statusCode, 'status', 404),
        ),
      );
      expect((await reread()).location, printer.location);
    });

    test('deleting a location ungroups its printers', () async {
      if (!hasLocations) {
        markTestSkipped('server predates printer locations');
        return;
      }
      final doomed = 'Loc-$stamp-doomed';
      await create(doomed);
      await locations.assign([printer.id], doomed);

      expect(await locations.delete([doomed]), 1);
      expect((await reread()).location, isNull);
      expect(
        (await locations.list()).map((l) => l.name),
        isNot(contains(doomed)),
      );
    });
  });
}
