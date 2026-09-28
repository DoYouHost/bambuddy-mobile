import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/endpoints.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../camera/camera_view.dart';
import '../camera/mjpeg_view.dart';

/// A printer's camera filling its wall tile (docs/tv-flavor.md §13.2, D12).
///
/// Live MJPEG while the stream holds. A stream the backoff cannot bring back
/// falls to a snapshot every [snapshotEvery] under a "live paused" marker, and
/// the stream keeps retrying behind it, so the tile goes live again on its own.
/// A snapshot that fails too leaves the tile dark under its status.
class WallCamera extends ConsumerStatefulWidget {
  const WallCamera({
    super.key,
    required this.printerId,
    required this.cacheWidth,
  });

  /// The interval the server's own camera wall polls snapshots at.
  static const snapshotEvery = Duration(seconds: 8);

  final int printerId;

  /// Decode width in physical pixels — the tile's, not the camera's.
  final int cacheWidth;

  @override
  ConsumerState<WallCamera> createState() => _WallCameraState();
}

class _WallCameraState extends ConsumerState<WallCamera> {
  /// The token a 401 already made us re-mint, so a refusal that is not an
  /// expiry cannot loop — the same guard as [CameraView].
  String? _remintedFor;

  @override
  Widget build(BuildContext context) {
    final baseUrl = ref.watch(serverProfileProvider)?.baseUrl;
    final token = ref.watch(cameraTokenProvider).valueOrNull;
    if (baseUrl == null || token == null) return const SizedBox.expand();
    return MjpegView(
      url: '$baseUrl${Endpoints.cameraStream(widget.printerId)}?token=$token',
      fit: BoxFit.cover,
      cacheWidth: widget.cacheWidth,
      loading: (_) => const SizedBox.expand(),
      retrying: (_) => const CameraRetryingBadge(),
      error: (context, error) {
        if (error is MjpegHttpStatus &&
            error.status == 401 &&
            _remintedFor != token) {
          _remintedFor = token;
          Future.microtask(() {
            if (!mounted) return;
            ref.read(cameraTokenServiceProvider).invalidate();
            ref.invalidate(cameraTokenProvider);
          });
          return const SizedBox.expand();
        }
        return _Snapshots(
          url:
              '$baseUrl${Endpoints.cameraSnapshot(widget.printerId)}'
              '?token=$token',
          cacheWidth: widget.cacheWidth,
        );
      },
    );
  }
}

class _Snapshots extends StatefulWidget {
  const _Snapshots({required this.url, required this.cacheWidth});

  final String url;
  final int cacheWidth;

  @override
  State<_Snapshots> createState() => _SnapshotsState();
}

class _SnapshotsState extends State<_Snapshots> {
  late final Timer _tick;
  int _n = 0;

  // A fresh query per shot, or the image cache answers with the first one.
  ImageProvider _shot(int n) =>
      ResizeImage(NetworkImage('${widget.url}&n=$n'), width: widget.cacheWidth);

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(WallCamera.snapshotEvery, (_) {
      final previous = _shot(_n);
      setState(() => _n++);
      unawaited(previous.evict());
    });
  }

  @override
  void dispose() {
    _tick.cancel();
    unawaited(_shot(_n).evict());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        Image(
          image: _shot(_n),
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => const SizedBox.expand(),
        ),
        Align(
          alignment: AlignmentDirectional.topEnd,
          child: Padding(
            padding: const EdgeInsets.all(8),
            // A pill does not ellipsize; on a narrow tile it shrinks instead.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: DashPill(
                label: l10n.wallLivePaused,
                accent: t.accentOrange,
                accentInk: t.accentOrangeInk,
                icon: Icons.pause_circle_outline_rounded,
                dense: true,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
