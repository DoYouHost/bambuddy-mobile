import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../core/diagnostics/diagnostic_recorder.dart';
import '../../core/diagnostics/log_event.dart';
import '../../core/diagnostics/log_tag.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common/state_views.dart';
import 'timelapse_export.dart';
import 'timelapse_format.dart';
import 'timelapse_url.dart';

/// Full-screen player for a print's timelapse.
///
/// The video is the one archive resource that behaves like the camera: the
/// server gates `GET /archives/{id}/timelapse` on the camera stream token in
/// `?token=`, not on the auth header, exactly as it does for thumbnails. So the
/// URL is minted here rather than routed through the Dio client.
///
/// A token that lapsed server-side (a restart, an early expiry) fails the same
/// way a missing video does — the platform player only reports "could not
/// open". Rather than guess from the message, the first failure re-mints the
/// token once and tries again; a second failure is reported as a failure.
///
/// The player can also just never start: ExoPlayer stays in its buffering state
/// and `initialize()` neither returns nor throws. A spinner that outlives
/// [_TimelapseScreenState._bootTimeout] therefore ends in a probe of the very
/// same URL, so the screen (and the diagnostic log behind a bug report) can say
/// whether the server refused it, never answered, or handed over a video the
/// device would not play.
class TimelapseScreen extends ConsumerStatefulWidget {
  const TimelapseScreen({super.key, required this.archiveId, this.title});

  final int archiveId;

  /// Title on the bar (the print name); falls back to l10n.
  final String? title;

  @override
  ConsumerState<TimelapseScreen> createState() => _TimelapseScreenState();
}

/// What the screen shows instead of a video, and what the log records.
enum _Failure {
  /// The player refused the URL outright, or there was nothing to open it with.
  open,

  /// The server answered, but not with the video (status carried alongside).
  http,

  /// The server hands the bytes over on demand, yet the player never started.
  stalled,
}

class _TimelapseScreenState extends ConsumerState<TimelapseScreen> {
  /// How long the player gets to reach its first frame.
  ///
  /// Covers a slow LAN and a large file, because the server writes the moov
  /// atom up front (`-movflags +faststart`) and honours byte ranges: playback
  /// starts on the head of the file, not on all of it. Past this, waiting
  /// longer has never been what was missing.
  static const _bootTimeout = Duration(seconds: 20);

  VideoPlayerController? _controller;

  /// Whether the controller reached its first frame. Kept apart from
  /// [_controller], which is set as soon as the player exists, so the screen
  /// can tell "constructed" from "playable".
  bool _ready = false;

  _Failure? _failure;
  int? _status;

  Timer? _watchdog;

  /// Camera token the current URL was built with — the download and the share
  /// need the same one, and re-minting it per action would be wasteful.
  String? _token;

  /// Bumped after an edit so the reload cannot be served the old video.
  int _version = 0;

  /// Fraction of the export that has arrived, null while indeterminate. Also
  /// the "an export is running" flag: the actions hide while it is set.
  double? _exportProgress;
  bool _exporting = false;

  /// Which load owns the screen. Bumped by [_retry] and by the watchdog so an
  /// earlier load still in flight can tell it has been replaced — same guard
  /// the G-code viewer uses.
  int _attempt = 0;

  bool _replaced(int attempt) => attempt != _attempt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _load({bool freshToken = false}) async {
    final attempt = _attempt;
    final TimelapseSource? source;
    try {
      source = await timelapseSource(
        ref,
        widget.archiveId,
        version: _version,
        freshToken: freshToken,
      );
    } catch (_) {
      if (!mounted || _replaced(attempt)) return;
      return _fail(_Failure.open);
    }
    if (!mounted || _replaced(attempt)) return;
    if (source == null) return _fail(_Failure.open);
    _token = source.token;

    final url = source.url;
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    setState(() => _controller = controller);
    _watchdog = Timer(_bootTimeout, () => _stalled(attempt, url));

    try {
      await controller.initialize();
    } catch (_) {
      _watchdog?.cancel();
      if (!mounted || _replaced(attempt)) return;
      if (!freshToken) {
        // Most likely a stale token; the re-mint costs one POST and spares the
        // user a retry they would otherwise have to tap themselves.
        ref.read(cameraTokenServiceProvider).invalidate();
        ref.invalidate(cameraTokenProvider);
        await _discard();
        if (!mounted) return;
        return _load(freshToken: true);
      }
      final status = await _probe(url);
      if (!mounted || _replaced(attempt)) return;
      return _fail(
        status == null || status < 400 ? _Failure.open : _Failure.http,
        status: status,
      );
    }

    _watchdog?.cancel();
    if (!mounted || _replaced(attempt)) return;
    setState(() => _ready = true);
    await controller.play();
  }

  /// The player has gone quiet past [_bootTimeout]. Ask the server the same
  /// question over HTTP: a refusal, a silence and a perfectly served file are
  /// three different bugs, and the spinner told them apart as none.
  Future<void> _stalled(int attempt, String url) async {
    if (!mounted || _replaced(attempt)) return;
    // Whatever the player is still doing, it no longer owns the screen.
    _attempt++;
    final status = await _probe(url);
    await _discard();
    if (!mounted) return;
    _fail(
      switch (status) {
        null => _Failure.open,
        final s when s >= 400 => _Failure.http,
        _ => _Failure.stalled,
      },
      status: status,
    );
  }

  /// Status of a one-kilobyte range request against [url], or null when the
  /// request itself did not come back. Deliberately the app's own Dio client:
  /// if this succeeds where the player hangs, the network is not the problem.
  Future<int?> _probe(String url) async {
    try {
      final res = await ref
          .read(apiClientProvider)
          .dio
          .get<List<int>>(
            url,
            options: Options(
              responseType: ResponseType.bytes,
              headers: const {'Range': 'bytes=0-1023'},
              validateStatus: (_) => true,
              receiveTimeout: const Duration(seconds: 10),
            ),
          );
      return res.statusCode;
    } catch (_) {
      return null;
    }
  }

  Future<void> _discard() async {
    final old = _controller;
    if (old == null) return;
    if (mounted) {
      setState(() {
        _controller = null;
        _ready = false;
      });
    }
    await old.dispose();
  }

  void _fail(_Failure failure, {int? status}) {
    DiagnosticRecorder.active?.add(
      LogSource.app,
      'timelapse',
      lvl: LogLevel.warn,
      fields: {
        'archive': widget.archiveId,
        'state': failure.name,
        'status': ?status,
      },
    );
    setState(() {
      _failure = failure;
      _status = status;
    });
  }

  Future<void> _retry() async {
    _watchdog?.cancel();
    _attempt++;
    setState(() {
      _failure = null;
      _status = null;
    });
    await _discard();
    if (!mounted) return;
    await _load(freshToken: true);
  }

  Future<void> _saveToGallery() => _export(
    (export, token, name) => export.saveToGallery(
      widget.archiveId,
      token: token,
      name: name,
      onProgress: _onExportProgress,
    ),
    announce: true,
  );

  Future<void> _share() => _export(
    (export, token, name) => export.share(
      widget.archiveId,
      token: token,
      name: name,
      onProgress: _onExportProgress,
    ),
    // The share sheet is its own confirmation; a snack bar behind it would
    // report success for something the user may still cancel.
    announce: false,
  );

  /// Dio reports progress per received chunk, which on a hundred-megabyte video
  /// is thousands of callbacks — each one rebuilding this whole screen, player
  /// included, for a bar that moves by a fraction of a pixel. Only a change the
  /// bar can actually show is worth a frame.
  void _onExportProgress(double? progress) {
    if (!mounted) return;
    final next = progress == null ? null : (progress * 100).floor() / 100;
    if (next == _exportProgress) return;
    setState(() => _exportProgress = next);
  }

  /// Downloads the video once and hands it to [action].
  ///
  /// The token is the one the player is already streaming with: if it were
  /// stale the video would not be on screen for the button to be pressed.
  Future<void> _export(
    Future<void> Function(TimelapseExport, String token, String name) action, {
    required bool announce,
  }) async {
    final token = _token;
    if (token == null) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final export = TimelapseExport(ref.read(timelapseRepositoryProvider));

    setState(() {
      _exporting = true;
      _exportProgress = null;
    });
    try {
      await action(export, token, widget.title ?? l10n.timelapseTitle);
      if (!mounted) return;
      if (announce) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.timelapseSaved)));
      }
    } catch (e) {
      final denied = e is TimelapseGalleryDenied;
      DiagnosticRecorder.active?.add(
        LogSource.app,
        'timelapse',
        lvl: LogLevel.warn,
        fields: {
          'archive': widget.archiveId,
          'state': denied ? 'export_denied' : 'export_failed',
        },
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            denied ? l10n.timelapseSaveDenied : l10n.timelapseSaveFailed,
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _exporting = false;
          _exportProgress = null;
        });
      }
    }
  }

  /// Opens the trim/speed editor and, if it re-encoded, reloads the player —
  /// the file behind the URL is a different video now.
  Future<void> _edit() async {
    // The editor opens its own player on the same file. Two decoders on one
    // recording is waste at best; on the way back the sound of the one left
    // running behind the editor is the giveaway.
    await _controller?.pause();
    if (!mounted) return;
    final name = Uri.encodeQueryComponent(widget.title ?? '');
    final edited = await context.push<bool>(
      '/timelapse/edit?archive=${widget.archiveId}&name=$name',
    );
    if (edited != true || !mounted) return;
    _version++;
    await _retry();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).timelapseEdited)),
    );
  }

  /// One line per way this can go wrong — the status is worth showing, not
  /// just logging: on a LAN server it is usually the whole diagnosis.
  String _message(AppLocalizations l10n) => switch (_failure!) {
    _Failure.open => l10n.timelapseError,
    _Failure.http => l10n.timelapseHttpError(_status ?? 0),
    _Failure.stalled => l10n.timelapseStalled,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = _controller;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: loggedAppBar(
        AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
          title: Text(
            widget.title ?? l10n.timelapseTitle,
            style: const TextStyle(
              fontFamily: DashTokens.fontUi,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: Colors.white,
            ),
          ),
          actions: _ready && !_exporting
              ? [
                  logTag(
                    'timelapse.save',
                    IconButton(
                      icon: const Icon(Icons.download_outlined),
                      tooltip: l10n.timelapseSave,
                      onPressed: _saveToGallery,
                    ),
                  ),
                  logTag(
                    'timelapse.share',
                    IconButton(
                      icon: const Icon(Icons.ios_share),
                      tooltip: l10n.timelapseShare,
                      onPressed: _share,
                    ),
                  ),
                  logTag(
                    'timelapse.edit',
                    IconButton(
                      icon: const Icon(Icons.content_cut),
                      tooltip: l10n.timelapseEdit,
                      onPressed: _edit,
                    ),
                  ),
                ]
              : null,
          // While an export runs the bar carries the progress instead of the
          // actions: the download is the only thing the screen is doing, and a
          // hundred-megabyte recording takes long enough to need saying so.
          bottom: _exporting
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(4),
                  child: LinearProgressIndicator(value: _exportProgress),
                )
              : null,
        ),
      ),
      body: _failure != null
          ? AsyncErrorView(
              message: _message(l10n),
              onRetry: _retry,
              retryLabel: l10n.retry,
              icon: Icons.videocam_off_outlined,
            )
          : controller == null || !_ready
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              top: false,
              child: Column(
                children: [
                  Expanded(
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: controller.value.aspectRatio,
                        child: logTag(
                          'timelapse.surface',
                          GestureDetector(
                            onTap: _togglePlay,
                            child: VideoPlayer(controller),
                          ),
                        ),
                      ),
                    ),
                  ),
                  _Controls(controller: controller, onToggle: _togglePlay),
                ],
              ),
            ),
    );
  }

  void _togglePlay() {
    final controller = _controller;
    if (controller == null) return;
    setState(() {
      controller.value.isPlaying ? controller.pause() : controller.play();
    });
  }
}

/// Transport bar: play/pause, a scrubbable progress line and the clock.
class _Controls extends StatelessWidget {
  const _Controls({required this.controller, required this.onToggle});

  final VideoPlayerController controller;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
        child: Row(
          children: [
            logTag(
              'timelapse.play_pause',
              IconButton(
                icon: Icon(
                  value.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                ),
                tooltip: value.isPlaying ? l10n.timelapsePause : l10n.timelapsePlay,
                onPressed: onToggle,
              ),
            ),
            Expanded(
              child: VideoProgressIndicator(
                controller,
                allowScrubbing: true,
                colors: const VideoProgressColors(
                  playedColor: Colors.white,
                  bufferedColor: Colors.white24,
                  backgroundColor: Colors.white12,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${formatClock(value.position.inMilliseconds / 1000)}'
              ' / ${formatClock(value.duration.inMilliseconds / 1000)}',
              style: const TextStyle(
                color: Colors.white,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }

}
