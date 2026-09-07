import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/endpoints.dart';
import '../../core/api/media_auth.dart';
import '../../providers.dart';

/// The video's URL and the credential baked into it — the exports need it
/// again, and re-minting it per action would be wasteful.
typedef TimelapseSource = ({String url, MediaAuth auth});

/// Builds the URL both the player and the editor's preview stream from.
///
/// This is the one archive route gated on the media credential rather than on
/// the auth header, so the URL carries its own and cannot go through the Dio
/// client's interceptor. When that credential is a header instead of a token
/// ([MediaAuth]), the player has to be handed it separately.
///
/// [version] is the cache-buster the web UI also appends: after an edit the
/// file behind the URL is a different video. Returns null when there is no
/// server profile; throws whatever minting the credential throws.
Future<TimelapseSource?> timelapseSource(
  WidgetRef ref,
  int archiveId, {
  int version = 0,
  bool freshToken = false,
}) async {
  final baseUrl = ref.read(serverProfileProvider)?.baseUrl;
  if (baseUrl == null) return null;
  final auth = await ref
      .read(mediaAuthServiceProvider)
      .auth(forceRefresh: freshToken);
  return (
    url: auth.sign(
      '$baseUrl${Endpoints.archiveTimelapse(archiveId)}?v=$version',
    ),
    auth: auth,
  );
}
