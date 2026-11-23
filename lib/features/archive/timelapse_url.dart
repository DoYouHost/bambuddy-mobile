import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/api/endpoints.dart';
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
VideoPlayerController timelapsePlayer(TimelapseSource source) {
  final url = Uri.parse(source.url);
  return VideoPlayerController.networkUrl(
    url,
    // ExoPlayer is not `dart:io`: Cloudflare Access's headers (#72) go on here.
    httpHeaders: {...source.auth.headers, ...edgeHeadersFor(url)},
  );
}

/// Asks for the first byte of the video with the Dart HTTP client, when
/// Cloudflare Access's credential is to ride with the player (#72).
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
/// The answer is not read: a server that ignores the range sends the whole file,
/// and only the status is wanted. Dio starts draining a streamed body at once,
/// whatever its listener does, so the request is cancelled when the status is
/// in: that closes the connection.
Future<void> checkEdgeAccess(Dio dio, TimelapseSource source) async {
  if (edgeHeadersFor(Uri.parse(source.url)).isEmpty) return;
  final cancel = CancelToken();
  final Response<ResponseBody> answer;
  try {
    answer = await dio.get<ResponseBody>(
      source.url,
      cancelToken: cancel,
      options: Options(
        responseType: ResponseType.stream,
        headers: {...source.auth.headers, 'Range': 'bytes=0-0'},
        validateStatus: (_) => true,
        receiveTimeout: const Duration(seconds: 10),
      ),
    );
  } on DioException catch (e) {
    cancel.cancel();
    if (e.error case final EdgeAccessException refused) throw refused;
    return;
  }
  // The status is in; the body is not wanted, and not waited for.
  cancel.cancel();
  final status = answer.statusCode ?? 0;
  if (status >= 300 && status < 400) {
    throw ApiException(AppErrorCode.badResponse, statusCode: status);
  }
}
