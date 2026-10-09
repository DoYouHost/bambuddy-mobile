import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/label_printer.dart';
import '../../core/demo/demo_label_printer.dart';
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
  ///
  /// An address is taken only once it answers as a label print server
  /// ([verify]): the platform can report a service before its address has
  /// resolved, which leaves a `.local` name that Android cannot use. Search
  /// goes on past a record that names the saved address or one that does not
  /// answer, because a fresher announcement may follow. And what the user
  /// chose in the meantime wins: the scan takes seconds, and a printer removed
  /// or replaced while it ran must not be put back.
  Future<void> refresh({
    Stream<List<DiscoveredLabelPrinter>> Function()? discover,
    Future<bool> Function(String baseUrl)? verify,
  }) async {
    final settings = ref.read(settingsRepositoryProvider);
    final name = settings.loadLabelPrinterName();
    final url = state;
    if (name == null || url == null) return;
    if (await ref.read(labelPrinterRepositoryProvider)?.info() != null) return;
    final answers =
        verify ??
        (String baseUrl) async =>
            await LabelPrinterRepository(
              createLabelPrinterDio(baseUrl),
            ).info() !=
            null;
    try {
      final Stream<List<DiscoveredLabelPrinter>> Function() search =
          discover ?? ref.read(labelPrinterDiscoveryProvider);
      await for (final found in search()) {
        final match = found.where((p) => p.name == name).firstOrNull;
        if (match == null || match.baseUrl == url) continue;
        if (!await answers(match.baseUrl)) continue;
        if (state != url || settings.loadLabelPrinterName() != name) return;
        await set(match.baseUrl, name: name);
        return;
      }
    } on Object {
      // No discovery on this device or network: the saved address stays.
    }
  }
}

/// A plain Dio, not [createBareDio]: that one feeds the bambuddy reachability
/// tracker and the bambuddy log filters, and this host is neither.
Dio createLabelPrinterDio(String baseUrl) {
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 4),
      receiveTimeout: const Duration(seconds: 8),
      sendTimeout: const Duration(seconds: 30),
    ),
  );
  // The demo's printer has no network address, so it is told by its name and
  // answered in process.
  if (isDemoLabelPrinter(baseUrl)) {
    dio.httpClientAdapter = demoLabelPrinterAdapter();
  }
  return dio;
}

/// The search for label print servers on the LAN — the demo's own in demo mode,
/// which has no network to search.
final labelPrinterDiscoveryProvider =
    Provider<Stream<List<DiscoveredLabelPrinter>> Function()>(
      (ref) => (ref.watch(serverProfileProvider)?.isDemo ?? false)
          ? demoDiscoverLabelPrinters
          : discoverLabelPrinters,
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
