import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/media_auth.dart';
import '../../providers.dart';

/// Reactive recovery for widgets rendering a media-authenticated
/// [Image.network] (URL carries `?token=`). On a 401/403 the token has expired
/// server-side; force a one-time re-mint — per token, so a genuinely broken
/// resource can't spin a refresh loop — which changes the URL and reloads the
/// image. Without this a stale token leaves every such image broken until an
/// app restart, since pull-to-refresh reloads the list but not the token.
///
/// Safety net paired with the proactive [mediaAuthRefresherProvider]: normally
/// the token is re-minted before it lapses; this catches early server-side
/// expiry (e.g. a server restart). A genuine 404 (no thumbnail) is ignored.
mixin MediaAuthImageRecovery<T extends ConsumerStatefulWidget>
    on ConsumerState<T> {
  /// Token we already forced a re-mint for — guards against a refresh loop.
  String? _remintedFor;

  /// Call from an [Image.network] `errorBuilder` with the failing [error] and
  /// the [auth] the URL was built with.
  void recoverMediaAuthOnError(Object error, MediaAuth auth) {
    // A header credential (API key) has nothing to re-mint: a 401 there means
    // the key itself was refused, and retrying only spins.
    final token = auth.queryToken;
    if (token == null) return;
    if (error is! NetworkImageLoadException) return;
    if (error.statusCode != 401 && error.statusCode != 403) return;
    if (_remintedFor == token) return;
    _remintedFor = token;
    Future.microtask(() {
      if (!mounted) return;
      ref.read(mediaAuthServiceProvider).invalidate();
      ref.invalidate(mediaAuthProvider);
    });
  }
}
