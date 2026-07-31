import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// The seed and difficulty the relay signed into a ticket.
@immutable
class PowChallenge {
  const PowChallenge({required this.seed, required this.bits});

  final String seed;
  final int bits;
}

/// Finds a nonce whose digest with [PowChallenge.seed] starts with enough zero
/// bits, on a background isolate.
///
/// The relay keeps this difficulty flat and small — about a second here — and
/// never raises it. Escalation lives in the not-before delay instead, because a
/// laptop grinds hashes orders of magnitude faster than a phone, so raising the
/// difficulty would cost an honest user minutes and an attacker nothing.
///
/// Off the main isolate because a second of hashing on the UI thread is a second
/// of dropped frames, and Android is entitled to throttle it either way.
Future<String> solvePow(PowChallenge challenge) async {
  // No work asked for, so no isolate: at zero bits the first nonce tried already
  // solves it, and spawning an isolate to discover that costs more than the
  // answer. Also what keeps this callable from a widget test, where a real
  // isolate needs `runAsync`.
  if (challenge.bits <= 0) return '0';
  return await compute(_solve, [challenge.seed, challenge.bits]);
}

String _solve(List<Object> args) {
  final seed = args[0] as String;
  final bits = args[1] as int;
  for (var nonce = 0;; nonce++) {
    final digest = sha256.convert(utf8.encode('$seed:$nonce')).bytes;
    if (_leadingZeroBits(digest) >= bits) return '$nonce';
  }
}

int _leadingZeroBits(List<int> bytes) {
  var count = 0;
  for (final byte in bytes) {
    if (byte == 0) {
      count += 8;
      continue;
    }
    var mask = 0x80;
    while (mask > 0 && byte & mask == 0) {
      count++;
      mask >>= 1;
    }
    break;
  }
  return count;
}
