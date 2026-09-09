import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';

/// Pull a response body straight into a file instead of into memory.
///
/// Anything the server hands over whole — a timelapse, a printer's file, a ZIP
/// of several — arrives at whatever size it happens to be, and reading it into
/// a list of bytes first costs that size in RAM and then copies it into the
/// file, peaking at twice it. A phone kills the app long before it complains.
///
/// One function for every such route, because the parts that are easy to get
/// wrong are the same each time: the method (a ZIP is asked for with a POST),
/// the deadline (see [receiveTimeout]), and turning a Dio failure into the
/// app's own exception so the caller can react to a 413 or a 507.
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

  /// How long the transfer may be idle. Dio measures this between chunks, not
  /// over the whole download, so it is a stall detector — but a server that
  /// assembles the file before answering is silent for as long as that takes,
  /// and looks exactly like a stall. [Duration.zero] switches the deadline off
  /// for the routes where the wait is the server working.
  Duration receiveTimeout = Duration.zero,
  void Function(int received, int total)? onProgress,

  /// Aborts a transfer already in flight. For the caller that has decided the
  /// bytes are no longer wanted — the screen that raised the download is gone —
  /// where finishing it would spend the user's data on a file about to be
  /// discarded.
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

/// A transfer's progress as a fraction, or null when it cannot be known.
///
/// A server that sends no `Content-Length` reports `total` as `-1`, and Dio
/// passes that straight through. Null is the answer the progress bar wants for
/// it — an indeterminate bar, rather than a full one or a crash on a negative
/// fraction. Every call site was writing the `total > 0` guard by hand, and one
/// of them writing `>=` would have divided by zero.
double? transferFraction(int done, int total) =>
    total > 0 ? done / total : null;

/// The same, rounded down to whole percent — for a bar that is rebuilt from
/// `setState`.
///
/// A large download reports progress far more often than a screen can paint,
/// and each report is a rebuild. Rounding to what the bar can actually show
/// turns thousands of rebuilds into a hundred, and the caller drops the frame
/// when this returns what it already had.
double? transferPercentStep(int done, int total) {
  final fraction = transferFraction(done, total);
  return fraction == null ? null : (fraction * 100).floor() / 100;
}

/// Dio options for an upload: no send or receive deadline.
///
/// A multipart POST of a 3MF or a cover image runs as long as the user's
/// upstream needs, and the client's ordinary timeouts describe a request that
/// is *stuck*, not one that is big. Left in place they cancel a healthy upload
/// on a slow connection, which reads to the user as the server refusing it.
Options uploadOptions() =>
    Options(sendTimeout: Duration.zero, receiveTimeout: Duration.zero);
