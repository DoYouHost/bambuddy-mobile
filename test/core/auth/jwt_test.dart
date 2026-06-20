import 'dart:convert';

import 'package:bambuddy_mobile/core/auth/jwt.dart';
import 'package:flutter_test/flutter_test.dart';

/// Składa minimalny JWT (header.payload.signature) z podanym payloadem.
/// Podpis jest atrapą — [jwtExpiry] go nie weryfikuje (czyta tylko `exp`).
String _jwt(Map<String, dynamic> payload) {
  String seg(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${seg({'alg': 'HS256', 'typ': 'JWT'})}.${seg(payload)}.sig';
}

void main() {
  test('czyta exp jako czas UTC', () {
    final token = _jwt({'exp': 1700000000, 'sub': 'u'});
    expect(
      jwtExpiry(token),
      DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000, isUtc: true),
    );
  });

  test('null/pusty/nie-JWT → null', () {
    expect(jwtExpiry(null), isNull);
    expect(jwtExpiry(''), isNull);
    expect(jwtExpiry('niejwt'), isNull);
    expect(jwtExpiry('a.b'), isNull); // za mało członów
  });

  test('brak exp albo exp nie-liczbowy → null', () {
    expect(jwtExpiry(_jwt({'sub': 'u'})), isNull);
    expect(jwtExpiry(_jwt({'exp': 'jutro'})), isNull);
  });

  test('uszkodzony payload (nie-base64/nie-JSON) → null', () {
    expect(jwtExpiry('aaa.!!!.bbb'), isNull);
  });
}
