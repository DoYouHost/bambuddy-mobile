import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/api/endpoints.dart';
import '../../core/diagnostics/diagnostic_recorder.dart';
import '../../core/diagnostics/log_event.dart';
import '../../core/settings/server_profile.dart';
import '../../core/theme/dash_text.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common/dash_progress.dart';
import '../common/state_views.dart';
import 'gcode_viewer_page.dart';

/// Full-screen 3D G-code preview, drawn by the app.
///
/// The WebView runs a page this app composes and ships — three.js plus the
/// slicer's own toolpath renderer, vendored from the server (see
/// `tool/gcode_viewer/PROVENANCE`). It is loaded with the server's base URL so
/// the one request it makes, for the G-code itself, is same-origin and carries
/// this session's auth header. Nothing is written to the WebView's storage.
///
/// It used to drive a viewer page the **server** served. That page was deleted
/// server-side in the 1.2.6 cycle and the app was left staring at an SPA it
/// could not drive (issue #17). What is left is
/// `GET /library/files/{id}/gcode` / `GET /archives/{id}/gcode`, which predate
/// both of the server's viewers — so this works on every server generation the
/// app supports, and stops depending on a page anyone can move.
class GcodeViewerScreen extends ConsumerStatefulWidget {
  const GcodeViewerScreen({
    super.key,
    this.archiveId,
    this.libraryFileId,
    this.plate,
    this.title,
  }) : assert(archiveId != null || libraryFileId != null,
            'archiveId or libraryFileId required');

  /// Archive id to view. Mutually exclusive with [libraryFileId].
  final int? archiveId;

  /// Library file id. Mutually exclusive with [archiveId].
  final int? libraryFileId;

  /// Plate number (1..N) for a multi-plate archive; null → first plate.
  /// Ignored for a library file, which the server always answers with plate 1.
  final int? plate;

  /// Title on the bar (e.g. print name); falls back to l10n.
  final String? title;

  @override
  ConsumerState<GcodeViewerScreen> createState() => _GcodeViewerScreenState();
}

class _GcodeViewerScreenState extends ConsumerState<GcodeViewerScreen> {
  /// Name the page posts its report to. Must match `entry.js`.
  static const _channel = 'BambuddyReport';

  /// How long the page gets to say its first word.
  ///
  /// A script that never reports `loading` never started — a bundle that failed
  /// to parse, a re-vendor that shipped broken JavaScript. No amount of waiting
  /// fixes that, so it is not worth [_silenceTimeout] of spinner to find out.
  static const _bootTimeout = Duration(seconds: 20);

  /// How long the page may then go quiet.
  ///
  /// A budget for *silence*, not for the work: the page beats every two seconds
  /// while it downloads, and again either side of the stretches that block the
  /// main thread. So this has to cover the longest single blocking step — the
  /// parse of an enormous plate — rather than the download, the parse and the
  /// mesh build added together.
  static const _silenceTimeout = Duration(seconds: 60);

  WebViewController? _controller;
  bool _ready = false;

  /// Whether the page has started drawing its own progress. Until then the app
  /// shows a spinner; after it, the page owns that job alone.
  bool _alive = false;
  GcodeViewerReport? _failure;
  Timer? _watchdog;

  /// Which load owns the screen. Bumped by [_retry], so an earlier one that is
  /// still in flight can tell that it has been replaced.
  int _attempt = 0;

  /// Whether a retry has taken the screen over since this load started.
  ///
  /// Kept apart from `mounted`, which the analyzer only recognises spelled out
  /// at the call site, and which answers a different question anyway: this one
  /// is about a load being replaced, not about the widget being gone.
  bool _replaced(int attempt) => attempt != _attempt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    super.dispose();
  }

  String get _gcodeUrl => gcodeSourceUrl(
        archiveId: widget.archiveId,
        libraryFileId: widget.libraryFileId,
        plate: widget.plate,
      );

  /// Loads the preview, in two halves that one gate separates.
  ///
  /// **Everything above the gate only reads** — credentials, colours, assets.
  /// Below it are the only side effects there are: the WebView, the watchdog
  /// and the state. A retry during the reading half therefore has nothing to
  /// undo, and a step added there cannot outlive its attempt however it is
  /// written. Adding one *below* the gate is the case to think about, and the
  /// block is short and marked so that it is obvious when you do.
  Future<void> _load() async {
    final attempt = _attempt;
    final profile = ref.read(serverProfileProvider);
    if (profile == null) {
      setState(() =>
          _failure = const GcodeViewerReport.failed(GcodeViewerError.network));
      return;
    }

    final headers = await _authHeaders(profile);
    if (!mounted || _replaced(attempt)) return;

    final filamentColors = await _filamentColors();
    if (!mounted || _replaced(attempt)) return;

    final shell = await rootBundle.loadString(gcodeViewerShellAsset);
    final bundle = await rootBundle.loadString(gcodeViewerBundleAsset);
    final fonts = await rootBundle.loadString(gcodeViewerFontsAsset);

    // ── the gate ──────────────────────────────────────────────────────────
    // The earlier checks only save work; this one is load-bearing. Nothing
    // below may run for a load the user has already walked away from.
    if (!mounted || _replaced(attempt)) return;

    final l10n = AppLocalizations.of(context);
    final document = buildViewerDocument(
      shell: shell,
      bundle: bundle,
      fonts: fonts,
      config: GcodeViewerConfig(
        gcodeUrl: _gcodeUrl,
        headers: headers,
        dark: Theme.of(context).brightness == Brightness.dark,
        // Already logical pixels, which is what a CSS pixel is in the WebView.
        insetRight: MediaQuery.systemGestureInsetsOf(context).right,
        filamentColors: filamentColors,
        labels: {
          'loading': l10n.gcodeViewerLoading,
          'parsing': l10n.gcodeViewerParsing,
          'failed': l10n.gcodeViewerError,
          'travels': l10n.gcodeViewerTravels,
          'colorByFilament': l10n.gcodeViewerColorByFilament,
          'colorByFeature': l10n.gcodeViewerColorByFeature,
          'colorByHeight': l10n.gcodeViewerColorByHeight,
          'colorByWidth': l10n.gcodeViewerColorByWidth,
          'singleLayer': l10n.gcodeSingleLayer,
        },
        // One label per slot the file actually has, so the page never has to
        // interpolate a translated string itself.
        filamentLabels: {
          for (var i = 0; i < filamentColors.length; i++)
            i: l10n.gcodeViewerFilamentSlot(i + 1),
        },
        featureLabels: {
          1: l10n.gcodeFeatureWall,
          2: l10n.gcodeFeatureSparseInfill,
          3: l10n.gcodeFeatureSolidInfill,
          4: l10n.gcodeFeatureSkirt,
          5: l10n.gcodeFeatureSupport,
          7: l10n.gcodeFeatureGapFill,
          9: l10n.gcodeFeatureBridge,
          10: l10n.gcodeFeatureIroning,
          11: l10n.gcodeFeaturePrimeTower,
        },
      ),
    );

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // Matches --bg in the page, so the WebView does not flash the wrong
      // ground before the first frame.
      ..setBackgroundColor(_pageBackground(context))
      ..addJavaScriptChannel(_channel, onMessageReceived: _onReport)
      ..setNavigationDelegate(
        NavigationDelegate(
          // Only a main-frame error is this page failing; the G-code request is
          // the page's own, and it reports that one itself with the status.
          onWebResourceError: (error) {
            if (error.isForMainFrame == true && mounted) {
              setState(() => _failure =
                  const GcodeViewerReport.failed(GcodeViewerError.script));
            }
          },
        ),
      )
      ..loadHtmlString(document, baseUrl: profile.baseUrl);

    _armWatchdog(_bootTimeout);

    setState(() => _controller = controller);
  }

  /// AMS colours in tool order, for colouring the toolpath by filament.
  ///
  /// Best-effort by design: the repository already swallows its own failures
  /// and answers with an empty list, and the preview is worth showing without
  /// colours — the page falls back to colouring by feature, which is the more
  /// useful view anyway on a single-material file.
  ///
  /// The slots are project-wide, so a multi-plate archive previewing plate 3
  /// still gets the right colours for the tools that plate uses.
  Future<List<String?>> _filamentColors() async {
    final requirements =
        await ref.read(slicerRepositoryProvider).filamentRequirements(
              id: widget.archiveId ?? widget.libraryFileId!,
              isArchive: widget.archiveId != null,
            );
    if (requirements.isEmpty) return const [];

    // `slot_id` is 1-based and the G-code's tool numbers are 0-based, so a
    // colour indexed straight by the slot lands one filament out.
    final highest = requirements.fold(0, (max, r) => r.slotId > max ? r.slotId : max);
    final colors = List<String?>.filled(highest, null);
    for (final requirement in requirements) {
      if (requirement.slotId < 1) continue;
      colors[requirement.slotId - 1] = requirement.color;
    }
    return colors;
  }

  /// Arms the single watchdog, replacing whatever it was waiting for.
  ///
  /// Two stages, because "the script never ran" and "the plate is enormous"
  /// deserve very different patience, and only the page can tell them apart —
  /// by speaking at all.
  void _armWatchdog(Duration limit) {
    _watchdog?.cancel();
    _watchdog = Timer(limit, () {
      if (!mounted || _ready || _failure != null) return;
      setState(() => _failure =
          const GcodeViewerReport.failed(GcodeViewerError.script));
    });
  }

  /// The page's `--bg`, so Flutter's ground and the WebView's agree.
  static Color _pageBackground(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF0B0F0C)
          : const Color(0xFFF6F8F4);

  Future<Map<String, String>> _authHeaders(ServerProfile profile) async {
    final creds = ref.read(credentialsStoreProvider);
    switch (profile.authMode) {
      case AuthMode.jwt:
        final jwt = await creds.readJwt();
        return jwt == null ? {} : {'Authorization': 'Bearer $jwt'};
      case AuthMode.apiKey:
        final key = await creds.readApiKey();
        return key == null ? {} : {'X-API-Key': key};
      case AuthMode.none:
        return {};
    }
  }

  void _onReport(JavaScriptMessage message) {
    final report = parseGcodeViewerReport(message.message);
    if (report == null || !mounted) return;

    if (report.error == null && !report.ready) {
      // Still watched, on the longer clock now: a page that says it is loading
      // and then hangs is exactly what the watchdog is for.
      _armWatchdog(_silenceTimeout);
      setState(() => _alive = true);
      return;
    }
    _watchdog?.cancel();

    if (report.ready) {
      setState(() => _ready = true);
      return;
    }
    // Worth a record: a preview that never appears looks, from the log alone,
    // exactly like a screen the user opened and left.
    DiagnosticRecorder.active?.add(
      LogSource.app,
      'gcode_viewer',
      lvl: LogLevel.warn,
      fields: {'state': report.error!.name, 'status': report.status},
    );
    setState(() => _failure = report);
  }

  /// The message for a failure, and whether trying again could change it.
  (String, bool) _failureText(AppLocalizations l10n, GcodeViewerReport f) =>
      switch (f.error!) {
        GcodeViewerError.empty => (l10n.gcodeViewerEmpty, false),
        GcodeViewerError.http => (
            l10n.gcodeViewerHttpError(f.status ?? 0),
            // 401/403 outlive a retry; a 5xx or a proxy hiccup does not.
            f.status == null || f.status! >= 500,
          ),
        GcodeViewerError.network || GcodeViewerError.script => (
            l10n.gcodeViewerError,
            true,
          ),
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = _controller;
    // The page has both themes now, so the bar follows the app instead of
    // being pinned dark over what might be a light canvas.
    final t = DashTokens.of(context);
    final failure = _failure;

    return Scaffold(
      backgroundColor: _pageBackground(context),
      appBar: loggedAppBar(
        AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: IconThemeData(color: t.textPrimary),
          title: Text(
            widget.title ?? l10n.gcodeViewerTitle,
            style: t.display.copyWith(letterSpacing: -0.3),
          ),
        ),
      ),
      body: failure != null
          ? _errorView(l10n, failure)
          : controller == null
              ? const DashLoading()
              // The page keeps its controls at its own edges, so it must not
              // extend under the navigation bar: down there the system takes
              // the touch and the slider never sees it.
              : SafeArea(
                  top: false,
                  child: Stack(
                    children: [
                      WebViewWidget(controller: controller),
                      // Only until the page speaks: from then on it draws its
                      // own progress, and two spinners would sit one on top of
                      // the other with the page's text between them.
                      if (!_alive)
                        const DashLoading(),
                    ],
                  ),
                ),
    );
  }

  Widget _errorView(AppLocalizations l10n, GcodeViewerReport failure) {
    final (message, canRetry) = _failureText(l10n, failure);
    return AsyncErrorView(
      message: message,
      // Nothing to retry on an unsliced file or a refusal: the only useful
      // button is the way out.
      onRetry: canRetry
          ? _retry
          : () => context.canPop() ? context.pop() : context.go('/'),
      retryLabel: canRetry ? l10n.retry : l10n.back,
      icon: failure.error == GcodeViewerError.empty
          ? Icons.layers_clear_outlined
          : Icons.broken_image_outlined,
    );
  }

  void _retry() {
    _watchdog?.cancel();
    _attempt++;
    setState(() {
      _failure = null;
      _ready = false;
      _alive = false;
      _controller = null;
    });
    _load();
  }
}

/// Path of the G-code for whichever source the viewer was opened on.
///
/// The plate rides as a query on the archive route only: the library route takes
/// no plate — it answers with the first `.gcode` in the file whatever is asked
/// (`library.py::get_gcode` reads `gcode_files[0]`).
///
/// Sending the plate matters on a multi-plate archive: without it the server
/// picks for us, and *which* plate that is has changed — newer servers take the
/// lowest-numbered plate, older ones the zip's first member — so the same
/// archive could preview as two different plates depending on the server.
///
/// Pure and top-level so it can be tested without a WebView: the screen it
/// serves cannot be built in a unit test, which is how the plate came to be
/// accepted here and passed by nobody.
String gcodeSourceUrl({
  required int? archiveId,
  required int? libraryFileId,
  int? plate,
}) {
  if (archiveId == null) {
    return Endpoints.libraryFileGcode(libraryFileId!);
  }
  final path = Endpoints.archiveGcode(archiveId);
  // A plate below 1 is not a plate; `Metadata/plate_0.gcode` does not exist and
  // asking for it would 404 a preview that would otherwise have worked.
  return plate == null || plate < 1 ? path : '$path?plate=$plate';
}
