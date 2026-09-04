import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Endpoints.archivePhoto', () {
    test('składa ścieżkę zdjęcia archiwum', () {
      expect(
        Endpoints.archivePhoto(82, 'finish_20260815_120000_ab12cd34.jpg'),
        '/api/v1/archives/82/photos/finish_20260815_120000_ab12cd34.jpg',
      );
    });

    test('koduje nazwę pliku — segment ścieżki, nie doklejona ścieżka', () {
      expect(
        Endpoints.archivePhoto(1, '../../etc/passwd'),
        '/api/v1/archives/1/photos/..%2F..%2Fetc%2Fpasswd',
      );
      expect(
        Endpoints.archivePhoto(1, 'zdjęcie z drukarki.jpg'),
        contains('zdj%C4%99cie%20z%20drukarki.jpg'),
      );
    });
  });
}
