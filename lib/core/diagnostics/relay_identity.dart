import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

const String _installIdKey = 'diagnostics.installId';

/// Stable, random identity for this installation, used only to meter reports.
///
/// Not a device id and deliberately not derived from one: the relay never sees
/// it in the clear anyway — it stores an HMAC — and rotating it is as simple as
/// reinstalling, which is the honest bound on what this can be used for. Its one
/// job is to make the wait before the next report escalate for whoever keeps
/// sending them.
Future<String> installId(SharedPreferences prefs) async {
  final existing = prefs.getString(_installIdKey);
  if (existing != null && existing.isNotEmpty) return existing;

  final fresh = _uuidV4();
  await prefs.setString(_installIdKey, fresh);
  return fresh;
}

/// Random.secure rather than a package: a UUID is sixteen random bytes with six
/// bits pinned, and pulling in a dependency to write that would be silly.
String _uuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 1
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}'
      '-${hex.substring(16, 20)}-${hex.substring(20)}';
}
