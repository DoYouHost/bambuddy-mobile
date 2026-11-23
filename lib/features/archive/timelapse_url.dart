import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/api/endpoints.dart';
import '../../core/api/loopback_proxy.dart';
import '../../core/api/media_auth.dart';
import '../../core/api/tls_overrides.dart';
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
///
/// [runId] is one print's own video; without it the archive's, which is its
/// latest print's.
Future<TimelapseSource?> timelapseSource(
  WidgetRef ref,
  int archiveId, {
  int? runId,
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
      '$baseUrl${runId == null ? Endpoints.archiveTimelapse(archiveId) : Endpoints.archiveRunTimelapse(archiveId, runId)}?v=$version',
    ),
    auth: auth,
  );
}

/// The player for a [TimelapseSource].
///
/// Both halves of the credential have to reach it: the token rides in the URL,
/// but an `X-API-Key` session has no token and carries a header instead, so a
/// player built from `source.url` alone loads nothing at all for those users.
/// One constructor, so the next screen cannot take only the half it can see —
/// the editor's preview did exactly that and failed silently.
///
/// ExoPlayer is not `dart:io`: a private CA or a client certificate (#62, #65)
/// means nothing to it, so for a server that needs one the video comes through
/// the app's loopback bridge instead, fetched by `dart:io` with the whole
/// identity, and the player is pointed at that.
Future<VideoPlayerController> timelapsePlayer(TimelapseSource source) async {
  final url = Uri.parse(source.url);
  if (needsLoopbackBridge(url, presentsTlsIdentity: presentsTlsIdentity())) {
    final lease = await LoopbackProxy.lease();
    return _BridgedPlayer(
      lease.expose(url, headers: source.auth.headers),
      lease,
    );
  }
  return VideoPlayerController.networkUrl(
    url,
    // ExoPlayer is not `dart:io`: Cloudflare Access's headers (#72) go on here.
    httpHeaders: {...source.auth.headers, ...edgeHeadersFor(url)},
  );
}

/// A player that gives the bridge back with itself.
class _BridgedPlayer extends VideoPlayerController {
  _BridgedPlayer(super.url, this._lease) : super.networkUrl();

  final LoopbackLease _lease;

  @override
  Future<void> dispose() async {
    try {
      await super.dispose();
    } finally {
      await _lease.release();
    }
  }
}

/// Asks about the video with the Dart HTTP client, when Cloudflare Access's
/// credential is to ride with the player (#72).
///
/// ExoPlayer follows a redirect with every header it holds, bambuddy's own
/// credential among them. Cloudflare answers a request it refuses with a
/// redirect to its team domain, and on to an identity provider when there is
/// one, so a refused request would carry that credential to a third party. The
/// Dart client stops at that redirect and `EdgeAccessProbe` names it, so the
/// player is only started for a request Cloudflare lets through.
///
/// Throws what it must not let the player meet: the [EdgeAccessException] the
/// question ended in, or, for any other redirect the Dart client stopped at (it
/// does not follow one to another origin), an [ApiException] with its status.
/// Any other answer, an error status included, is the player's to report, so is
/// not thrown here.
///
/// A `HEAD`, because only the status is wanted and it has no body: a `GET` with a
/// byte range is answered with the whole file by a server that ignores the range,
/// and stopping that download was a race (cancelling the read leaves the
/// connection open until the next write finds it closed). Cloudflare answers a
/// `HEAD` as it does the `GET`: Access decides before the server is asked.
Future<void> checkEdgeAccess(Dio dio, TimelapseSource source) async {
  if (edgeHeadersFor(Uri.parse(source.url)).isEmpty) return;
  final Response<void> answer;
  try {
    answer = await dio.request<void>(
      source.url,
      options: Options(
        method: 'HEAD',
        headers: source.auth.headers,
        validateStatus: (_) => true,
        receiveTimeout: const Duration(seconds: 10),
      ),
    );
  } on DioException catch (e) {
    if (e.error case final EdgeAccessException refused) throw refused;
    return;
  }
  final status = answer.statusCode ?? 0;
  if (status >= 300 && status < 400) {
    throw ApiException(AppErrorCode.badResponse, statusCode: status);
  }
}
