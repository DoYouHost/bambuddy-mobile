import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';

/// Reactive recovery for widgets rendering a camera-token-authenticated
/// [Image.network] (URL carries `?token=`). On a 401/403 the token has expired
/// server-side; force a one-time re-mint — per token, so a genuinely broken
/// resource can't spin a refresh loop — which changes the URL and reloads the
/// image. Without this a stale token leaves every such image broken until an
/// app restart, since pull-to-refresh reloads the list but not the token.
///
/// Safety net paired with the proactive [cameraTokenRefresherProvider]: normally
/// the token is re-minted before it lapses; this catches early server-side
/// expiry (e.g. a server restart). A genuine 404 (no thumbnail) is ignored.
mixin CameraTokenImageRecovery<T extends ConsumerStatefulWidget>
    on ConsumerState<T> {
  /// Token we already forced a re-mint for — guards against a refresh loop.
  String? _remintedFor;

  /// Call from an [Image.network] `errorBuilder` with the failing [error] and
  /// the [token] baked into the URL.
  void recoverCameraTokenOnError(Object error, String token) {
    if (error is! NetworkImageLoadException) return;
    if (error.statusCode != 401 && error.statusCode != 403) return;
    if (_remintedFor == token) return;
    _remintedFor = token;
    Future.microtask(() {
      if (!mounted) return;
      ref.read(cameraTokenServiceProvider).invalidate();
      ref.invalidate(cameraTokenProvider);
    });
  }
}
