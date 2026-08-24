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
}) =>
    guard(() async {
      final res = await dio.download(
        path,
        savePath,
        data: data,
        queryParameters: queryParameters,
        options: Options(method: method, receiveTimeout: receiveTimeout),
        onReceiveProgress: onProgress,
      );
      return res.headers.value(Headers.contentTypeHeader);
    });
