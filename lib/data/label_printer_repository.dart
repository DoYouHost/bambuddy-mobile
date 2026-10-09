import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/models/label_printer.dart';

/// The label print server on the LAN. It has no authentication and nothing to
/// do with the bambuddy session, so it gets a Dio of its own per address.
class LabelPrinterRepository {
  LabelPrinterRepository(this._dio);

  final Dio _dio;

  /// Identity and capabilities, or null when the address does not answer as a
  /// label print server (nothing there, or some other service).
  Future<LabelPrinterInfo?> info() async {
    try {
      final res = await _dio.get<Object?>('/info');
      final data = res.data;
      if (!LabelPrinterInfo.isLabelPrinter(data)) return null;
      return LabelPrinterInfo.fromJson(Map<String, dynamic>.from(data as Map));
    } on DioException {
      return null;
    }
  }

  /// Prints [pdf] — every page is one label — [copies] times each.
  ///
  /// [cutEvery] counts labels across the whole job, copies included: 1 cuts
  /// after every label, 0 never in between. [cutAtEnd] is the cut after the
  /// last one.
  ///
  /// The server's own sentence (`detail`) is kept for a 400: it names the file
  /// and why it was refused (`wrong_format` with the size found), which nothing
  /// in the app knows.
  Future<void> printPdf(
    Uint8List pdf, {
    required String filename,
    int copies = 1,
    bool cutAtEnd = true,
    int cutEvery = 0,
  }) => guardKeepingDetail(() async {
    await _dio.post<Object?>(
      '/print',
      data: FormData.fromMap({
        'files': MultipartFile.fromBytes(pdf, filename: filename),
        'copies': copies,
        'cut_at_end': cutAtEnd,
        'cut_every': cutEvery,
      }),
      // A Pi Zero needs seconds per label; the default 15 s would cut a job.
      options: Options(receiveTimeout: const Duration(minutes: 2)),
    );
  });
}
