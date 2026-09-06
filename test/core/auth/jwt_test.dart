import 'dart:convert';

import 'package:bambuddy_mobile/core/auth/jwt.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds minimal JWT (header.payload.signature) with given payload.
/// Signature is a stub — [jwtExpiry] does not verify it (reads only `exp`).
String _jwt(Map<String, dynamic> payload) {
  String seg(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${seg({'alg': 'HS256', 'typ': 'JWT'})}.${seg(payload)}.sig';
}

void main() {
  test('reads exp as UTC time', () {
    final token = _jwt({'exp': 1700000000, 'sub': 'u'});
    expect(
      jwtExpiry(token),
      DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000, isUtc: true),
    );
  });

  test('null/empty/not-JWT → null', () {
    expect(jwtExpiry(null), isNull);
    expect(jwtExpiry(''), isNull);
    expect(jwtExpiry('niejwt'), isNull);
    expect(jwtExpiry('a.b'), isNull); // too few segments
  });

  test('missing exp or exp non-numeric → null', () {
    expect(jwtExpiry(_jwt({'sub': 'u'})), isNull);
    expect(jwtExpiry(_jwt({'exp': 'jutro'})), isNull);
  });

  test('corrupted payload (not-base64/not-JSON) → null', () {
    expect(jwtExpiry('aaa.!!!.bbb'), isNull);
  });
}
