import 'dart:convert';
import 'dart:io';

import 'package:bambuddy_mobile/core/network/label_printer_discovery.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsd/nsd.dart';

void main() {
  group('labelPrinterFromService', () {
    test('prefers the IPv4 address and reads the TXT hints', () {
      final found = labelPrinterFromService(
        Service(
          name: 'rpi-label-printer',
          host: 'rpi-label-printer.local',
          port: 8000,
          addresses: [
            InternetAddress('fe80::1'),
            InternetAddress('192.168.1.40'),
          ],
          txt: {
            'model': utf8.encode('QL-600'),
            'label': utf8.encode('62x29'),
            'path': null,
          },
        ),
      );
      expect(found!.baseUrl, 'http://192.168.1.40:8000');
      expect(found.name, 'rpi-label-printer');
      expect(found.model, 'QL-600');
      expect(found.labelId, '62x29');
    });

    test('falls back to the host name when no address resolved', () {
      final found = labelPrinterFromService(
        const Service(name: 'p', host: 'pi.local', port: 9000),
      );
      expect(found!.baseUrl, 'http://pi.local:9000');
      expect(found.model, isNull);
    });

    test('is null until port and host are known', () {
      expect(labelPrinterFromService(const Service(name: 'p')), isNull);
      expect(
        labelPrinterFromService(const Service(name: 'p', port: 8000)),
        isNull,
      );
      expect(
        labelPrinterFromService(const Service(name: 'p', host: 'pi')),
        isNull,
      );
    });
  });
}
