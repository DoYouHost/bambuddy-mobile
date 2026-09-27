import 'package:bambuddy_mobile/core/demo/demo_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// The gate between a reviewer's fabricated dataset and a real server: what it
/// lets through never reaches the network, and what it turns away must.
void main() {
  group('isDemoUrl', () {
    test(
      'the magic address is recognized whatever scheme it was typed with',
      () {
        for (final url in [
          'http://demo',
          'https://demo',
          'http://demo.bambuddy.app',
          'https://demo.bambuddy.app',
        ]) {
          expect(DemoConfig.isDemoUrl(url), isTrue, reason: url);
        }
      },
    );

    test('the host is matched regardless of case or port', () {
      expect(DemoConfig.isDemoUrl('http://DEMO'), isTrue);
      expect(DemoConfig.isDemoUrl('http://Demo.Bambuddy.App:8080'), isTrue);
    });

    test('the saved profile URL is itself a demo URL', () {
      expect(DemoConfig.isDemoUrl(DemoConfig.baseUrl), isTrue);
    });

    test('a real server is not answered from the fabricated dataset', () {
      for (final url in [
        'http://192.168.1.10:8080',
        'http://bambuddy.local',
        'http://demo.example.com',
        'http://mydemo',
        'http://demo.bambuddy.app.example.com',
      ]) {
        expect(DemoConfig.isDemoUrl(url), isFalse, reason: url);
      }
    });

    test('a bare host counts only once it has been normalized', () {
      // `Uri` reads a schemeless string as a path, so there is no host to
      // match — the caller normalizes before asking.
      expect(DemoConfig.isDemoUrl('demo'), isFalse);
      expect(DemoConfig.isDemoUrl('http://demo'), isTrue);
    });

    test('nothing typed, or something that is not a URL, is not demo', () {
      for (final url in ['', '   ', '://', 'http://']) {
        expect(DemoConfig.isDemoUrl(url), isFalse, reason: '"$url"');
      }
    });
  });
}
