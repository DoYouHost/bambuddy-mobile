/// The page the G-code preview runs in, and the protocol it talks back over.
///
/// Kept apart from the screen so both are testable without a WebView: this file
/// knows nothing about Flutter, and everything in it is a pure function of its
/// arguments.
///
/// The page is composed here rather than fetched, and loaded with the server's
/// base URL, which is what makes `fetch` inside it same-origin with the API.
/// Nothing is written to the WebView's storage — the credentials ride as
/// request headers and die with the page.
library;

import 'dart:convert';

/// Asset paths of the two halves of the document.
const gcodeViewerShellAsset = 'assets/gcode/viewer.html';
const gcodeViewerBundleAsset = 'assets/gcode/viewer.js';

/// Placeholders the shell reserves; both are replaced exactly once.
const _configMarker = '__BB_CONFIG__';
const _bundleMarker = '__BB_BUNDLE__';

/// What the page needs to know before it starts.
class GcodeViewerConfig {
  const GcodeViewerConfig({
    required this.gcodeUrl,
    required this.headers,
    required this.dark,
    required this.labels,
    required this.featureLabels,
    this.filamentLabels = const {},
    this.filamentColors = const [],
    this.insetRight = 0,
    this.volume,
  });

  /// Server-relative path of the G-code (`/api/v1/...`). Relative on purpose:
  /// the document's base URL is the server, so this stays same-origin even when
  /// the user's host is behind a proxy that rewrites nothing else.
  final String gcodeUrl;

  /// Auth headers for that one request — `X-API-Key` or `Authorization`,
  /// whichever this session uses, and empty when the server wants neither.
  final Map<String, String> headers;

  final bool dark;

  /// Status and control strings, already localized.
  final Map<String, String> labels;

  /// Toolpath type → localized name, for the legend. The renderer ships its
  /// own labels, but they are upstream's Korean.
  final Map<int, String> featureLabels;

  /// Tool index → localized slot name, for the legend in filament mode.
  final Map<int, String> filamentLabels;

  /// AMS colours in tool order — index 0 is the slot the G-code calls `T0`.
  /// A slot the file records no colour for is null and falls back to the first
  /// known colour. Empty when the server could not say, which leaves the page
  /// on feature colouring and hides the switch.
  final List<String?> filamentColors;

  /// The system's right-edge gesture inset, in CSS pixels (which are logical
  /// pixels here). The layer slider sits inside it: a control flush against the
  /// screen edge competes with the back swipe and loses. `env()` cannot see
  /// this from inside a WebView, so it has to be handed over.
  final double insetRight;

  /// Build volume in mm, for the bed grid; the viewer falls back to 256³.
  final ({double x, double y, double z})? volume;

  Map<String, Object?> toJson() => {
        'gcodeUrl': gcodeUrl,
        'headers': headers,
        'dark': dark,
        'insetRight': insetRight,
        'filamentColors': filamentColors,
        'labels': {
          ...labels,
          // The legend indexes by number, and JSON keys are strings.
          'features': {
            for (final e in featureLabels.entries) '${e.key}': e.value,
          },
          'filaments': {
            for (final e in filamentLabels.entries) '${e.key}': e.value,
          },
        },
        if (volume != null)
          'volume': {'x': volume!.x, 'y': volume!.y, 'z': volume!.z},
      };
}

/// Builds the single self-contained document the WebView loads.
///
/// [shell] and [bundle] are the two assets; nothing else is fetched, because a
/// relative `<script src>` would resolve against the **server** (the document's
/// base URL) and ask it for a file it has never heard of.
String buildViewerDocument({
  required String shell,
  required String bundle,
  required GcodeViewerConfig config,
}) {
  // `<` is escaped throughout so no label can close the script element early;
  // inside a JSON string `<` is the same character.
  final json = jsonEncode(config.toJson()).replaceAll('<', r'\u003c');
  return shell
      .replaceFirst(_configMarker, 'window.__BB = $json;')
      .replaceFirst(_bundleMarker, bundle);
}

/// Why the page could not show a preview.
enum GcodeViewerError {
  /// The request never got an answer — server down, proxy in the way.
  network,

  /// The server answered, and refused: [GcodeViewerReport.status] says how.
  http,

  /// A 200 with no toolpath in it. The file was never sliced.
  empty,

  /// The page itself threw. A bug on our side, not a state of the server.
  script,
}

/// What the page reported. Exactly one of [ready] / [error] is set.
class GcodeViewerReport {
  const GcodeViewerReport.ready()
      : ready = true,
        error = null,
        status = null;

  const GcodeViewerReport.failed(this.error, {this.status}) : ready = false;

  final bool ready;
  final GcodeViewerError? error;

  /// HTTP status behind [GcodeViewerError.http]; null for every other error.
  final int? status;

  @override
  bool operator ==(Object other) =>
      other is GcodeViewerReport &&
      other.ready == ready &&
      other.error == error &&
      other.status == status;

  @override
  int get hashCode => Object.hash(ready, error, status);

  @override
  String toString() => ready ? 'ready' : 'failed($error, $status)';
}

/// Reads a channel message; `null` for anything not in the protocol.
///
/// Deliberately strict. The report decides between showing the preview and
/// showing an error, so a message that is not understood may only be ignored —
/// guessing either way replaces a working preview with an error page, or hides
/// a failure behind a spinner that never ends.
GcodeViewerReport? parseGcodeViewerReport(String message) {
  final parts = message.trim().split(':');
  if (parts.first == 'ready' && parts.length == 1) {
    return const GcodeViewerReport.ready();
  }
  if (parts.first != 'error' || parts.length < 2) return null;

  return switch (parts[1]) {
    'network' when parts.length == 2 =>
      const GcodeViewerReport.failed(GcodeViewerError.network),
    'empty' when parts.length == 2 =>
      const GcodeViewerReport.failed(GcodeViewerError.empty),
    'script' when parts.length == 2 =>
      const GcodeViewerReport.failed(GcodeViewerError.script),
    // `error:http:404` — the status is worth carrying: 401 and 404 send the
    // user to completely different places, and a bug report that says which
    // one it was saves a round trip.
    'http' when parts.length == 3 => GcodeViewerReport.failed(
        GcodeViewerError.http,
        status: int.tryParse(parts[2]),
      ),
    _ => null,
  };
}
