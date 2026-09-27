import 'package:bambuddy_mobile/features/common/web_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('webLinkOrNull', () {
    test('passes a web address through', () {
      expect(
        webLinkOrNull('https://makerworld.com/models/1')?.host,
        'makerworld.com',
      );
      expect(webLinkOrNull('http://192.168.1.5:8000/x'), isNotNull);
      expect(webLinkOrNull('  HTTPS://Example.com  '), isNotNull);
    });

    test('nothing to open', () {
      expect(webLinkOrNull(null), isNull);
      expect(webLinkOrNull(''), isNull);
      expect(webLinkOrNull('   '), isNull);
    });

    test('refuses every scheme that would start another app', () {
      for (final raw in const [
        'intent://scan/#Intent;scheme=zxing;package=com.example;end',
        'market://details?id=com.example',
        'javascript:alert(1)',
        'file:///sdcard/secret.txt',
        'content://com.example.provider/x',
        'tel:+48123456789',
        'bambuddy://config?url=http://evil&key=k',
      ]) {
        expect(webLinkOrNull(raw), isNull, reason: raw);
      }
    });

    test('refuses a web scheme with no host, and text that is no URL', () {
      expect(webLinkOrNull('https:'), isNull);
      expect(webLinkOrNull('http:/relative'), isNull);
      expect(webLinkOrNull('example.com/page'), isNull);
      expect(webLinkOrNull('http://[::1'), isNull);
    });
  });
}
