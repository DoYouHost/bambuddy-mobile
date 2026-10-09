import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/label_printer.dart';
import '../../data/label_printer_repository.dart';
import '../../providers.dart';

/// The label print server the user chose, as a base URL; null while none is.
final labelPrinterUrlProvider =
    NotifierProvider<LabelPrinterUrlNotifier, String?>(
      LabelPrinterUrlNotifier.new,
    );

class LabelPrinterUrlNotifier extends Notifier<String?> {
  @override
  String? build() =>
      ref.watch(settingsRepositoryProvider).loadLabelPrinterUrl();

  Future<void> set(String? url) async {
    await ref.read(settingsRepositoryProvider).saveLabelPrinterUrl(url);
    state = url;
  }
}

/// A plain Dio, not [createBareDio]: that one feeds the bambuddy reachability
/// tracker and the bambuddy log filters, and this host is neither.
Dio createLabelPrinterDio(String baseUrl) => Dio(
  BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 4),
    receiveTimeout: const Duration(seconds: 8),
    sendTimeout: const Duration(seconds: 30),
  ),
);

/// Null while no server is chosen.
final labelPrinterRepositoryProvider = Provider<LabelPrinterRepository?>((ref) {
  final url = ref.watch(labelPrinterUrlProvider);
  return url == null
      ? null
      : LabelPrinterRepository(createLabelPrinterDio(url));
});

/// What the chosen server answers right now; null when none is chosen or it
/// does not answer. Re-read with `ref.invalidate`.
final labelPrinterInfoProvider = FutureProvider.autoDispose<LabelPrinterInfo?>(
  (ref) => ref.watch(labelPrinterRepositoryProvider)?.info() ?? Future.value(),
);
