/// Which signed gap `POST /printers/{id}/bed-jog` has to be sent for an arrow
/// on the movement sheet.
///
/// The route takes a nozzle-bed gap (positive opens it) and, on the servers
/// that shipped between v0.2.4.1 (commit a2c9eef8) and the fix for bambuddy
/// #1334 (commit 2c7c97c1, released in v1.2.5.6), flipped that sign itself for
/// the A1 family. The jog is unguarded — firmware ignores soft endstops on
/// MQTT G-code — so a wrong sign drives the nozzle into the plate. Where the
/// server generation cannot be told, the app offers no Z jog at all.
library;

import 'dart:convert';

import '../api/server_version.dart';
import '../models/printer_capabilities.dart';

/// How the connected server treats `distance` on an A1 / A1 Mini.
enum BedJogConvention {
  /// Sent to the printer unchanged, as the route documents.
  direct,

  /// Negated for the models in [_legacyFlippedModels] before it is sent.
  flippedOnA1,

  /// Nothing seen settles it.
  unknown,
}

/// The old server's `A1_MODELS`, compared the way it compared them
/// (`model.strip().upper() in A1_MODELS`) — so "A1M", the A2L and the
/// alternate codes were never flipped, on any server.
const _legacyFlippedModels = {
  'A1',
  'A1 MINI',
  'A1-MINI',
  'A1MINI',
  'N1',
  'N2S',
};

/// Whether this printer's jog sign depends on the server generation at all.
bool bedJogDependsOnServer(String? model) =>
    model != null && _legacyFlippedModels.contains(model.trim().toUpperCase());

/// The convention a server of [version] follows, or [BedJogConvention.unknown]
/// for the one build number that spans both: every 1.2.6 daily reports
/// `1.2.6b1`, before and after the fix alike.
BedJogConvention bedJogConventionFor(ServerVersion? version) {
  if (version == null) return BedJogConvention.unknown;
  if (version.baseBelow((0, 2, 4, 1))) return BedJogConvention.direct;
  if (version.baseBelow((1, 2, 5, 6))) return BedJogConvention.flippedOnA1;
  final isBeta126 =
      (version.major, version.minor, version.patch, version.micro) ==
          (1, 2, 6, 0) &&
      version.isPrerelease &&
      version.prereleaseNum <= 1;
  return isBeta126 ? BedJogConvention.unknown : BedJogConvention.direct;
}

/// The one sentence only the flipping servers carry in the route's `distance`
/// description. Released text never changes, so its absence on a server that
/// lists the route means "direct" however that description is reworded later.
const _flipSentence = 'translates this into the right G-code Z sign';

/// Reads the convention off the server's `/openapi.json`. The whole path item
/// is searched rather than a parameter walked, so a reshaped schema cannot
/// turn a known answer into an unknown one.
BedJogConvention bedJogConventionFromOpenApi(Object? document) {
  if (document is! Map) return BedJogConvention.unknown;
  final paths = document['paths'];
  if (paths is! Map) return BedJogConvention.unknown;
  for (final entry in paths.entries) {
    final path = entry.key;
    if (path is String && path.endsWith('/printers/{printer_id}/bed-jog')) {
      return jsonEncode(entry.value).contains(_flipSentence)
          ? BedJogConvention.flippedOnA1
          : BedJogConvention.direct;
    }
  }
  return BedJogConvention.unknown;
}

/// The `distance` to send for an arrow, or `null` when it cannot be known.
///
/// On a bed-slinger "up" lifts the toolhead and opens the gap; everywhere else
/// it raises the plate and closes it.
double? bedJogDistance({
  required bool up,
  required double step,
  required String? model,
  required BedJogConvention convention,
}) {
  final opensGap = isBedSlinger(model) ? up : !up;
  final gap = opensGap ? step : -step;
  if (!bedJogDependsOnServer(model)) return gap;
  return switch (convention) {
    BedJogConvention.direct => gap,
    BedJogConvention.flippedOnA1 => -gap,
    BedJogConvention.unknown => null,
  };
}
