import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/models/timelapse.dart';
import 'streamed_download.dart';

/// Everything about a print's timelapse except playing it: the metadata and
/// filmstrip the editor draws, the re-encode it asks for, and the download.
///
/// Only the video bytes need the camera token in `?token=`; info, thumbnails
/// and processing go through the ordinary authenticated client.
class TimelapseRepository {
  TimelapseRepository(this._dio);

  final Dio _dio;

  /// How long the server may take to re-encode.
  ///
  /// The route runs ffmpeg inline and answers when it finishes, so this is a
  /// budget for the work itself, not for a stalled connection: a minutes-long
  /// 1080p re-encode on a Pi is the case that sets it, and the client's
  /// 15-second default would abort a job the server then completes anyway.
  static const _processTimeout = Duration(minutes: 15);

  Future<TimelapseInfo> info(int archiveId) => guard(() async {
    final res = await _dio.get<Map<String, dynamic>>(
      Endpoints.archiveTimelapseInfo(archiveId),
    );
    return TimelapseInfo.fromJson(res.data ?? const {});
  });

  /// [count] frames, each [width] pixels wide — the server caps them at 30
  /// and 320 and renders every one with ffmpeg, so asking for more is paid
  /// for in latency.
  Future<TimelapseFilmstrip> filmstrip(
    int archiveId, {
    int count = 14,
    int width = 160,
  }) => guard(() async {
    final res = await _dio.get<Map<String, dynamic>>(
      Endpoints.archiveTimelapseThumbnails(archiveId),
      queryParameters: {'count': count, 'width': width},
    );
    return TimelapseFilmstrip.fromJson(res.data ?? const {});
  });

  /// Re-encodes the recording in place. [trimEnd] null keeps the tail.
  ///
  /// Always `save_mode=replace`: the server's `new` writes a file alongside
  /// the original that no archive field then points at, so it would produce a
  /// video the app has no way to play back.
  Future<TimelapseProcessResult> process(
    int archiveId, {
    required double trimStart,
    double? trimEnd,
    required double speed,
  }) => guard(() async {
    final form = FormData.fromMap({
      'trim_start': trimStart,
      'trim_end': ?trimEnd,
      'speed': speed,
      'save_mode': 'replace',
    });
    final res = await _dio.post<Map<String, dynamic>>(
      Endpoints.archiveTimelapseProcess(archiveId),
      data: form,
      options: Options(
        receiveTimeout: _processTimeout,
        sendTimeout: _processTimeout,
      ),
    );
    return TimelapseProcessResult.fromJson(res.data ?? const {});
  });

  /// Streams the video to [savePath] and answers with the `Content-Type` the
  /// server sent, which is the only place the container is stated: the same
  /// route serves MP4, AVI and MKV.
  ///
  /// Takes the camera [token] because this is the one route of the four that
  /// reads `?token=` instead of the auth header.
  Future<String?> downloadTo(
    int archiveId, {
    required String token,
    required String savePath,
    void Function(int received, int total)? onProgress,
  }) => streamDownload(
    _dio,
    Endpoints.archiveTimelapse(archiveId),
    savePath,
    queryParameters: {'token': token},
    // A hundred-megabyte recording over a slow LAN outlasts the default, and
    // this route streams from a file the server already has: it is answering
    // within seconds or not at all, so a stall deadline still means something
    // here.
    receiveTimeout: const Duration(minutes: 10),
    onProgress: onProgress,
  );
}
