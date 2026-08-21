import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../core/diagnostics/log_tag.dart';
import '../../core/models/timelapse.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../core/api/api_exceptions.dart';
import '../../providers.dart';
import '../common/api_failure_snack.dart';
import '../common/confirm_dialog.dart';
import '../common/dash_async.dart';
import '../common/dash_snack.dart';
import 'timelapse_format.dart';
import 'timelapse_providers.dart';
import 'timelapse_trim.dart';
import 'timelapse_trim_strip.dart';
import 'timelapse_url.dart';

/// Trim and speed for a recorded timelapse.
///
/// Nothing is edited on the device: the screen collects three numbers and the
/// server re-encodes with ffmpeg. That call is synchronous and can run for
/// minutes on a small host, so the save keeps the screen up with a progress
/// state rather than returning to the player and leaving the work invisible.
///
/// The result overwrites the recording — the server's only other mode writes a
/// file no archive field points at — so the save is behind a confirmation.
class TimelapseEditorScreen extends ConsumerStatefulWidget {
  const TimelapseEditorScreen({super.key, required this.archiveId, this.title});

  final int archiveId;
  final String? title;

  @override
  ConsumerState<TimelapseEditorScreen> createState() =>
      _TimelapseEditorScreenState();
}

class _TimelapseEditorScreenState extends ConsumerState<TimelapseEditorScreen> {
  static const _speeds = [0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 4.0];

  /// Shortest clip the editor will let you keep. Below a second the trim is
  /// almost certainly a mis-drag, and ffmpeg's output would be unwatchable.
  static const _minClip = 1.0;

  /// How long the preview gets to produce a first frame before the editor
  /// gives up on it. The trim and speed controls work without a preview, so
  /// this fails quietly and quickly rather than holding the screen hostage.
  static const _previewTimeout = Duration(seconds: 20);

  RangeValues? _trim;
  double _speed = 1;
  bool _saving = false;

  VideoPlayerController? _preview;

  /// Whether the user wants the preview running. Not the same as the player's
  /// `isPlaying`, which also goes false at the end of the file and in the
  /// middle of the loop's own seek — this is what those two then resume from.
  bool _wantPlay = false;

  /// Guards the loop against re-entering while its seek is still in flight.
  bool _seeking = false;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  @override
  void dispose() {
    _preview?.removeListener(_holdInsideTrim);
    _preview?.dispose();
    super.dispose();
  }

  Future<void> _loadPreview() async {
    VideoPlayerController? controller;
    try {
      final source = await timelapseSource(ref, widget.archiveId);
      if (source == null || !mounted) return;
      controller = VideoPlayerController.networkUrl(Uri.parse(source.url));
      await controller.initialize().timeout(_previewTimeout);
    } catch (_) {
      // No preview, no editor failure: trim and speed are numbers the server
      // applies, and it is the server's copy that gets re-encoded either way.
      await controller?.dispose();
      return;
    }
    if (!mounted) {
      await controller.dispose();
      return;
    }
    controller.addListener(_holdInsideTrim);
    setState(() => _preview = controller);
  }

  /// Loops playback back to the start of the trimmed region when it runs past
  /// the end of it — the same rule the web editor's preview follows, so what
  /// you watch here is what the saved file will contain.
  ///
  /// Only the *end* is policed. A seek lands on a frame, not on an exact
  /// millisecond, so a rule that also pulled the position up to the start
  /// would re-fire on its own undershoot and seek in a loop: the decoder
  /// spends the whole time flushing and the picture never moves.
  void _holdInsideTrim() {
    final controller = _preview;
    final trim = _trim;
    if (controller == null || trim == null || !_wantPlay || _seeking) return;

    final position = controller.value.position.inMilliseconds / 1000;
    if (!timelapseReachedEnd(position, trim.end)) return;

    _seeking = true;
    () async {
      try {
        await controller.seekTo(_at(trim.start));
        // Reaching the natural end of the file stops playback, so resuming is
        // part of looping rather than a no-op.
        if (mounted && _wantPlay) await controller.play();
      } finally {
        // A seek that throws must not leave the guard set: the loop would go
        // quiet for the rest of the screen's life.
        _seeking = false;
      }
    }();
  }

  Future<void> _togglePreview() async {
    final controller = _preview;
    final trim = _trim;
    if (controller == null || trim == null) return;

    if (_wantPlay) {
      setState(() => _wantPlay = false);
      await controller.pause();
      return;
    }

    setState(() => _wantPlay = true);
    // Anywhere outside the trim (including the tail left by a previous loop)
    // would play material the save is about to drop.
    final position = controller.value.position.inMilliseconds / 1000;
    if (timelapseNeedsRewind(position, trim.start, trim.end)) {
      await controller.seekTo(_at(trim.start));
    }
    await controller.setPlaybackSpeed(_speed);
    await controller.play();
  }

  /// Parks the preview on the handle that was just released, so the trim is
  /// chosen against a frame rather than against a number.
  ///
  /// Takes the edge from the strip: once a drag ends, this screen's own copy
  /// of the range has already moved, so comparing before-and-after here could
  /// only ever name the same handle.
  Future<void> _previewEdge(double edge) async {
    final controller = _preview;
    if (controller == null) return;
    if (_wantPlay) {
      setState(() => _wantPlay = false);
      await controller.pause();
    }
    await controller.seekTo(_at(edge));
  }

  /// Drag on the strip outside the handles: move the playhead, leaving
  /// playback as it was — scrubbing a running preview is how you check a cut.
  void _scrub(double seconds) => _preview?.seekTo(_at(seconds));

  static Duration _at(double seconds) =>
      Duration(milliseconds: (seconds * 1000).round());

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final info = ref.watch(timelapseInfoProvider(widget.archiveId));

    return Scaffold(
      appBar: dashAppBar(
        context,
        title: l10n.timelapseEditTitle,
        actions: [
          if (info.hasValue && !_saving)
            logTag(
              'timelapse_edit.save',
              TextButton(
                onPressed: () => _save(info.requireValue),
                child: Text(l10n.timelapseEditSave),
              ),
            ),
        ],
      ),
      body: dashAsync(
        context,
        info,
        onRetry: () => ref.invalidate(timelapseInfoProvider(widget.archiveId)),
        skipLoadingOnReload: false,
        skipLoadingOnRefresh: false,
        data: (data) => _saving ? _savingView(l10n) : _editor(l10n, data),
      ),
    );
  }

  Widget _savingView(AppLocalizations l10n) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            l10n.timelapseEditProcessing,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    ),
  );

  Widget _editor(AppLocalizations l10n, TimelapseInfo info) {
    final trim = _trim ??= RangeValues(0, info.duration);
    final output = (trim.end - trim.start) / _speed;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (_preview case final preview?) ...[
          _Preview(
            controller: preview,
            playing: _wantPlay,
            onToggle: _togglePreview,
          ),
          const SizedBox(height: 16),
        ],
        _SectionHeader(
          icon: Icons.content_cut,
          label: l10n.timelapseEditTrim,
          value:
              '${formatClock(trim.start)} – ${formatClock(trim.end)}'
              ' (${formatClock(trim.end - trim.start)})',
        ),
        const SizedBox(height: 8),
        _TrimStrip(
          archiveId: widget.archiveId,
          preview: _preview,
          duration: info.duration,
          trim: trim,
          minClip: _minClip,
          onTrimChanged: (v) => setState(() => _trim = v),
          onTrimCommitted: _previewEdge,
          onSeek: _scrub,
        ),
        const SizedBox(height: 16),
        _SectionHeader(
          icon: Icons.speed,
          label: l10n.timelapseEditSpeed,
          value: l10n.timelapseEditOutput(formatClock(output)),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final speed in _speeds)
              logTag(
                'timelapse_edit.speed',
                ChoiceChip(
                  label: Text(formatSpeed(speed)),
                  selected: _speed == speed,
                  onSelected: (_) {
                    setState(() => _speed = speed);
                    // Straight onto the running preview, so the chip is
                    // audible in the picture rather than only in the maths.
                    _preview?.setPlaybackSpeed(speed);
                  },
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          l10n.timelapseEditSource(
            formatClock(info.duration),
            info.width,
            info.height,
          ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Future<void> _save(TimelapseInfo info) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final trim = _trim ?? RangeValues(0, info.duration);

    final confirmed = await confirmDialog(
      context,
      title: l10n.timelapseEditSaveTitle,
      message: l10n.timelapseEditSaveMessage,
      confirmLabel: l10n.timelapseEditSave,
      destructive: true,
      icon: Icons.movie_filter_outlined,
      id: 'timelapse_edit_save',
    );
    if (!confirmed || !mounted) return;

    setState(() => _saving = true);
    try {
      final result = await ref
          .read(timelapseRepositoryProvider)
          .process(
            widget.archiveId,
            trimStart: trim.start,
            // Sending the untouched tail as an explicit end is harmless and
            // keeps the request the same shape whether or not it was dragged.
            trimEnd: trim.end,
            speed: _speed,
          );
      if (!mounted) return;
      if (!result.ok) {
        setState(() => _saving = false);
        messenger.snack(result.message);
        return;
      }
      // The player reloads on a true result — the file behind its URL changed.
      context.pop(true);
    } catch (e) {
      // Anything at all, not just AppApiException: a 200 whose body does not
      // parse throws a TypeError, and leaving `_saving` set would freeze the
      // screen on a spinner for work that already finished.
      if (!mounted) return;
      setState(() => _saving = false);
      if (e is AppApiException) {
        showApiFailure(messenger, e, l10n, action: 'timelapse_edit.save');
      } else {
        messenger.snack(l10n.connectFailed);
      }
    }
  }
}

/// The trimmed clip as it will look after saving, with the big centre play
/// button the web editor also puts over its preview.
class _Preview extends StatelessWidget {
  const _Preview({
    required this.controller,
    required this.playing,
    required this.onToggle,
  });

  final VideoPlayerController controller;

  /// The editor's intent, not the player's state: at the loop point the
  /// player stops for a moment, and a button that flashed back to ▶ there
  /// would read as the preview having ended.
  final bool playing;

  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) => ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: value.aspectRatio,
          child: logTag(
            'timelapse_edit.preview',
            GestureDetector(
              onTap: onToggle,
              child: ColoredBox(
                color: Colors.black,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    VideoPlayer(controller),
                    if (!playing)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Icon(
                            Icons.play_arrow,
                            size: 36,
                            color: Theme.of(context).colorScheme.onPrimary,
                            semanticLabel: l10n.timelapsePlay,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The trim control, fed with the frames the server renders and — while a
/// preview exists — with its live position for the playhead.
///
/// The frames are orienting, not load-bearing: if they never arrive the strip
/// still trims, against a plain background.
class _TrimStrip extends ConsumerWidget {
  const _TrimStrip({
    required this.archiveId,
    required this.preview,
    required this.duration,
    required this.trim,
    required this.minClip,
    required this.onTrimChanged,
    required this.onTrimCommitted,
    required this.onSeek,
  });

  final int archiveId;
  final VideoPlayerController? preview;
  final double duration;
  final RangeValues trim;
  final double minClip;
  final ValueChanged<RangeValues> onTrimChanged;
  final ValueChanged<double> onTrimCommitted;
  final ValueChanged<double> onSeek;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strip = ref.watch(timelapseFilmstripProvider(archiveId));

    Widget build(double? position) => TimelapseTrimStrip(
      frames: strip.valueOrNull?.frames ?? const [],
      loading: strip.isLoading,
      duration: duration,
      trim: trim,
      minClip: minClip,
      position: position,
      onTrimChanged: onTrimChanged,
      onTrimCommitted: onTrimCommitted,
      onSeek: onSeek,
    );

    final controller = preview;
    if (controller == null) return build(null);
    // Rebuilt from the player's own value, so the playhead follows playback
    // rather than the screen's setState calls.
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) =>
          build(value.position.inMilliseconds / 1000),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Text(label, style: theme.textTheme.titleSmall),
        const Spacer(),
        Text(value, style: theme.textTheme.bodySmall),
      ],
    );
  }
}
