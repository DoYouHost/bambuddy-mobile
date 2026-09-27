import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';

/// Pull a response body straight into a file instead of into memory: a
/// timelapse or a ZIP read into a byte list first peaks at twice its size in
/// RAM, and a phone kills the app long before it complains.
///
/// Returns the `Content-Type` the server sent, which for some routes is the
/// only statement of what the file actually is.
Future<String?> streamDownload(
  Dio dio,
  String path,
  String savePath, {
  String method = 'GET',
  Object? data,
  Map<String, dynamic>? queryParameters,

  /// How long the transfer may be idle — Dio measures between chunks, so a
  /// server assembling the file before answering looks exactly like a stall.
  /// [Duration.zero] switches the deadline off where the wait is that work.
  Duration receiveTimeout = Duration.zero,
  void Function(int received, int total)? onProgress,

  /// Aborts a transfer in flight, for a caller whose screen is gone: finishing
  /// would spend the user's data on a file about to be discarded.
  CancelToken? cancelToken,
}) => guard(() async {
  final res = await dio.download(
    path,
    savePath,
    data: data,
    queryParameters: queryParameters,
    options: Options(method: method, receiveTimeout: receiveTimeout),
    onReceiveProgress: onProgress,
    cancelToken: cancelToken,
  );
  return res.headers.value(Headers.contentTypeHeader);
});

/// A transfer's progress as a fraction, or null when it cannot be known: a
/// server that sends no `Content-Length` reports `total` as `-1` and Dio passes
/// that through, which the progress bar wants as indeterminate.
double? transferFraction(int done, int total) =>
    total > 0 ? done / total : null;

/// The same, rounded down to whole percent: a large download reports progress
/// far more often than a screen can paint, and the caller drops the frame when
/// this returns what it already had.
double? transferPercentStep(int done, int total) {
  final fraction = transferFraction(done, total);
  return fraction == null ? null : (fraction * 100).floor() / 100;
}

/// Dio options for an upload: no deadline at all. A multipart POST runs as long
/// as the user's upstream needs, and the ordinary timeouts describe a request
/// that is *stuck*, not one that is big — they cancel a healthy slow upload,
/// which reads as the server refusing it.
Options uploadOptions() =>
    Options(sendTimeout: Duration.zero, receiveTimeout: Duration.zero);
