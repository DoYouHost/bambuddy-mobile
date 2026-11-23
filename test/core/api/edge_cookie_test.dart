import 'dart:convert';

import 'package:bambuddy_mobile/core/api/edge_access.dart';
import 'package:bambuddy_mobile/core/api/edge_cookie.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// The browser sign-in of Cloudflare Access (#72): what is made of the cookie it
// leaves. The WebView itself and Android's CookieManager are not here; the
// channel is played by a mock, and the cookie store by a fake.

String _jwt(Map<String, Object?> payload) {
  String part(Object o) =>
      base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${part({'alg': 'RS256'})}.${part(payload)}.sig';
}

final _expiry = DateTime.utc(2026, 11, 24, 12);
int get _expSeconds => _expiry.millisecondsSinceEpoch ~/ 1000;

class _FakeJar implements EdgeCookieJar {
  _FakeJar([this.values = const []]);

  List<String> values;
  final asked = <(Uri, String)>[];
  var cleared = false;

  @override
  Future<List<String>> cookies(Uri url, String name) async {
    asked.add((url, name));
    return values;
  }

  @override
  Future<void> clear() async => cleared = true;
}

void main() {
  group('BrowserSession.fromCookie', () {
    test('ends where the token says', () {
      final session = BrowserSession.fromCookie(
        host: 'printers.example.com',
        cookie: _jwt({'exp': _expSeconds}),
      )!;
      expect(session.expiresAt, _expiry);
      expect(session.host, 'printers.example.com');
      expect(session.headers, {
        'Cookie': 'CF_Authorization=${_jwt({'exp': _expSeconds})}',
      });
    });

    test('is nothing for a cookie that cannot be told to expire', () {
      for (final cookie in [
        '',
        'opaque',
        'a.b',
        _jwt({'sub': 'u'}),
      ]) {
        expect(
          BrowserSession.fromCookie(host: 'h.example.com', cookie: cookie),
          isNull,
          reason: cookie,
        );
      }
    });

    test('is nothing without a host', () {
      expect(
        BrowserSession.fromCookie(host: '', cookie: _jwt({'exp': _expSeconds})),
        isNull,
      );
    });

    test('has ended at its expiry, not a moment before', () {
      final session = BrowserSession.fromCookie(
        host: 'h.example.com',
        cookie: _jwt({'exp': _expSeconds}),
      )!;
      expect(
        session.isExpired(_expiry.subtract(const Duration(seconds: 1))),
        isFalse,
      );
      expect(session.isExpired(_expiry), isTrue);
      expect(session.isExpired(_expiry.add(const Duration(days: 1))), isTrue);
    });
  });

  group('cookieValues', () {
    test('finds a cookie among others', () {
      expect(
        cookieValues('a=1; CF_Authorization=tok; c=3', 'CF_Authorization'),
        ['tok'],
      );
      expect(cookieValues('CF_Authorization=tok', 'CF_Authorization'), ['tok']);
    });

    test('keeps every one, in the order given', () {
      expect(cookieValues('k=old; a=1; k=new', 'k'), ['old', 'new']);
    });

    test('keeps a value that holds an equals sign', () {
      expect(cookieValues('k=a=b==', 'k'), ['a=b==']);
    });

    test('matches the whole name only', () {
      expect(
        cookieValues(
          'X_CF_Authorization=no; CF_Authorization_2=no',
          'CF_Authorization',
        ),
        isEmpty,
      );
    });

    test('is empty for nothing, an empty value and a header without it', () {
      expect(cookieValues(null, 'k'), isEmpty);
      expect(cookieValues('', 'k'), isEmpty);
      expect(cookieValues('k=', 'k'), isEmpty);
      expect(cookieValues('a=1; b=2', 'k'), isEmpty);
      expect(cookieValues('junk; ;', 'k'), isEmpty);
    });

    test('tolerates the spacing a browser uses', () {
      expect(
        cookieValues(' a=1 ;CF_Authorization = tok ', 'CF_Authorization'),
        ['tok'],
      );
    });
  });

  group('the channel', () {
    const channel = MethodChannel(
      'page.codeberg.morganmlgman.bambuddy/edge_cookie',
    );

    setUp(() => TestWidgetsFlutterBinding.ensureInitialized());
    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    void answer(Future<Object?>? Function(MethodCall call) handler) =>
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, handler);

    test(
      'asks the CookieManager for the URL and reads the cookie out',
      () async {
        MethodCall? seen;
        answer((call) async {
          seen = call;
          return 'a=1; CF_Authorization=tok';
        });
        final values = await const WebViewEdgeCookieJar().cookies(
          Uri.parse('https://printers.example.com'),
          'CF_Authorization',
        );
        expect(values, ['tok']);
        expect(seen!.method, 'cookies');
        expect(seen!.arguments, {'url': 'https://printers.example.com'});
      },
    );

    test('is nothing when the store holds none', () async {
      answer((_) async => null);
      expect(
        await const WebViewEdgeCookieJar().cookies(
          Uri.parse('https://h.example.com'),
          'k',
        ),
        isEmpty,
      );
    });

    test('is nothing where there is no such channel', () async {
      expect(
        await const WebViewEdgeCookieJar().cookies(
          Uri.parse('https://h.example.com'),
          'k',
        ),
        isEmpty,
      );
      await const WebViewEdgeCookieJar().clear();
    });

    test('is nothing when the host refuses', () async {
      answer((_) async => throw PlatformException(code: 'refused'));
      expect(
        await const WebViewEdgeCookieJar().cookies(
          Uri.parse('https://h.example.com'),
          'k',
        ),
        isEmpty,
      );
    });

    test('clear tells the CookieManager', () async {
      String? method;
      answer((call) async {
        method = call.method;
        return null;
      });
      await const WebViewEdgeCookieJar().clear();
      expect(method, 'clear');
    });
  });

  group('EdgeSignIn.check', () {
    final now = DateTime.utc(2026, 11, 24, 9);

    EdgeSignIn signIn(_FakeJar jar) =>
        EdgeSignIn(host: 'printers.example.com', jar: jar, now: () => now);

    test('is nothing while the store holds no cookie', () async {
      expect(await signIn(_FakeJar()).check(), isNull);
    });

    test('is the session once a valid cookie is there', () async {
      final jar = _FakeJar([
        _jwt({'exp': _expSeconds}),
      ]);
      final session = await signIn(jar).check();
      expect(session!.host, 'printers.example.com');
      expect(session.expiresAt, _expiry);
      // Asked about the app's own host, over https, for Access's cookie.
      expect(jar.asked, [
        (Uri.parse('https://printers.example.com'), 'CF_Authorization'),
      ]);
    });

    test('takes the first good cookie, not the first one', () async {
      // An older cookie left by a previous sign-in is listed first.
      final ended = _jwt({'exp': _expSeconds - 24 * 3600});
      final good = _jwt({'exp': _expSeconds});
      final session = await signIn(_FakeJar(['opaque', ended, good])).check();
      expect(session!.cookie, good);
    });

    test('takes the one that ends last, whatever the order', () async {
      // An earlier sign-in's cookie that has not ended yet, and the one just
      // issued: neither end of the store's order says which is current.
      final earlier = _jwt({'exp': _expSeconds - 3600});
      final latest = _jwt({'exp': _expSeconds});
      for (final order in [
        [earlier, latest],
        [latest, earlier],
      ]) {
        final session = await signIn(_FakeJar(order)).check();
        expect(session!.cookie, latest, reason: '$order');
      }
    });

    test('is nothing for a cookie that has already ended', () async {
      final ended = _jwt({'exp': _expSeconds - 24 * 3600});
      expect(await signIn(_FakeJar([ended])).check(), isNull);
    });

    test('is nothing for a cookie that is not a token', () async {
      expect(await signIn(_FakeJar(['opaque-value'])).check(), isNull);
    });
  });
}
