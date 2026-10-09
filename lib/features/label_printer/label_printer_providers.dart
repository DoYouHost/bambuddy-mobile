import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/label_printer.dart';
import '../../core/network/label_printer_discovery.dart';
import '../../core/settings/label_print_prefs.dart';
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

  /// [name] is the mDNS instance name when the server was found by search; it
  /// is what [refresh] looks for after the address changes.
  Future<void> set(String? url, {String? name}) async {
    final settings = ref.read(settingsRepositoryProvider);
    await settings.saveLabelPrinterUrl(url);
    await settings.saveLabelPrinterName(url == null ? null : name);
    state = url;
  }

  /// Follows a server that moved: when the saved address no longer answers and
  /// the server was found by search, looks for it again by name and takes its
  /// new address. Silent on every failure — the print itself reports a server
  /// that cannot be reached.
  Future<void> refresh({
    Stream<List<DiscoveredLabelPrinter>> Function() discover =
        discoverLabelPrinters,
  }) async {
    final name = ref.read(settingsRepositoryProvider).loadLabelPrinterName();
    final url = state;
    if (name == null || url == null) return;
    if (await ref.read(labelPrinterRepositoryProvider)?.info() != null) return;
    try {
      await for (final found in discover()) {
        final match = found.where((p) => p.name == name).firstOrNull;
        if (match == null) continue;
        if (match.baseUrl != url) await set(match.baseUrl, name: name);
        return;
      }
    } on Object {
      // No discovery on this device or network: the saved address stays.
    }
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

/// What the label sheet remembers between uses.
final labelPrintPrefsProvider =
    NotifierProvider<LabelPrintPrefsNotifier, LabelPrintPrefs>(
      LabelPrintPrefsNotifier.new,
    );

class LabelPrintPrefsNotifier extends Notifier<LabelPrintPrefs> {
  @override
  LabelPrintPrefs build() =>
      ref.watch(settingsRepositoryProvider).loadLabelPrintPrefs();

  Future<void> set(LabelPrintPrefs prefs) async {
    state = prefs;
    await ref.read(settingsRepositoryProvider).saveLabelPrintPrefs(prefs);
  }
}
