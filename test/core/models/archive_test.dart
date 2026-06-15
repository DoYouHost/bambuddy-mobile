import 'package:bambuddy_mobile/core/models/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
  group('Archive.fromJson', () {
    test('parsuje wpis archiwum, ignorując nieznane pola', () {
      final archive = Archive.fromJson(
          readFixture('archive.json') as Map<String, dynamic>);

      expect(archive.id, 82);
      expect(archive.displayName, 'The Smoothy - Y Splitter Connector');
      expect(archive.status, 'completed');
      expect(archive.filamentType, 'PETG');
      expect(archive.cost, 0.51);
      expect(archive.isFavorite, isFalse);
      expect(archive.designer, 'JDJDJD');
      expect(archive.createdAt, isA<DateTime>());
    });

    test('displayName: printName ma pierwszeństwo nad filename', () {
      const withName = Archive(
        id: 1,
        filename: 'plik.gcode.3mf',
        status: 'completed',
        printName: 'Ładna nazwa',
      );
      const withoutName = Archive(
        id: 2,
        filename: 'plik.gcode.3mf',
        status: 'completed',
      );

      expect(withName.displayName, 'Ładna nazwa');
      expect(withoutName.displayName, 'plik.gcode.3mf');
    });

    test('nieznane klucze nie wywołują wyjątku', () {
      expect(
        () => Archive.fromJson(const {
          'id': 1,
          'filename': 'test.3mf',
          'status': 'completed',
          'totally_unknown_future_field': {'nested': true},
        }),
        returnsNormally,
      );
    });

    test('minimalny payload (id/filename/status) parsuje się bez błędu', () {
      final archive = Archive.fromJson(const {
        'id': 5,
        'filename': 'minimalny.gcode',
        'status': 'archived',
      });

      expect(archive.id, 5);
      expect(archive.filename, 'minimalny.gcode');
      expect(archive.isFavorite, isFalse,
          reason: 'domyślna wartość false gdy pole nieobecne');
      expect(archive.displayName, 'minimalny.gcode',
          reason: 'brak printName → fallback na filename');
    });
  });
}
