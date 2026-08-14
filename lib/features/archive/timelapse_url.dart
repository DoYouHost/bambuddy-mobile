import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/endpoints.dart';
import '../../providers.dart';

/// The video's URL and the token baked into it — the exports need the token
/// again, and re-minting it per action would be wasteful.
typedef TimelapseSource = ({String url, String token});

/// Builds the URL both the player and the editor's preview stream from.
///
/// This is the one archive route gated on `?token=` (the camera stream token)
/// rather than on the auth header, so the URL carries its own credential and
/// cannot go through the Dio client's interceptor.
///
/// [version] is the cache-buster the web UI also appends: after an edit the
/// file behind the URL is a different video. Returns null when there is no
/// server profile; throws whatever minting the token throws.
Future<TimelapseSource?> timelapseSource(
  WidgetRef ref,
  int archiveId, {
  int version = 0,
  bool freshToken = false,
}) async {
  final baseUrl = ref.read(serverProfileProvider)?.baseUrl;
  if (baseUrl == null) return null;
  final token = await ref
      .read(cameraTokenServiceProvider)
      .token(forceRefresh: freshToken);
  return (
    url:
        '$baseUrl${Endpoints.archiveTimelapse(archiveId)}'
        '?token=$token&v=$version',
    token: token,
  );
}
