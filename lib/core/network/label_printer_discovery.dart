import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nsd/nsd.dart' as nsd;

/// DNS-SD type the label print server announces itself under.
const labelPrinterServiceType = '_labelprinter._tcp';

/// A label print server found on the LAN.
class DiscoveredLabelPrinter {
  const DiscoveredLabelPrinter({
    required this.name,
    required this.baseUrl,
    this.model,
    this.labelId,
  });

  /// The service instance name, e.g. `rpi-label-printer`.
  final String name;

  /// `http://<ip>:<port>`, ready for [LabelPrinterRepository].
  final String baseUrl;

  /// TXT `model` and `label` — only a hint; `/info` is the truth.
  final String? model;
  final String? labelId;
}

/// The resolved service as a [DiscoveredLabelPrinter], or null while it has no
/// usable address yet.
///
/// The IPv4 address is preferred over the host name: the server's README warns
/// that Android does not resolve `.local` names reliably.
DiscoveredLabelPrinter? labelPrinterFromService(nsd.Service service) {
  final port = service.port;
  if (port == null) return null;
  final ip = service.addresses
      ?.where((a) => a.type == InternetAddressType.IPv4)
      .map((a) => a.address)
      .firstOrNull;
  final host = ip ?? service.host;
  if (host == null || host.isEmpty) return null;
  String? txt(String key) {
    final bytes = service.txt?[key];
    return bytes == null ? null : utf8.decode(bytes, allowMalformed: true);
  }

  return DiscoveredLabelPrinter(
    name: service.name ?? host,
    baseUrl: 'http://$host:$port',
    model: txt('model'),
    labelId: txt('label'),
  );
}

/// Label print servers answering on the LAN, as a growing list, until
/// [timeout] — then the stream closes and the discovery is released (Android
/// documents discovery as expensive).
///
/// Throws on the first listen when the platform refuses to start a discovery.
Stream<List<DiscoveredLabelPrinter>> discoverLabelPrinters({
  Duration timeout = const Duration(seconds: 6),
}) {
  late final StreamController<List<DiscoveredLabelPrinter>> controller;
  nsd.Discovery? discovery;
  Timer? timer;

  Future<void> stop() async {
    timer?.cancel();
    final d = discovery;
    discovery = null;
    if (d != null) await nsd.stopDiscovery(d);
  }

  controller = StreamController(
    onListen: () async {
      try {
        final d = discovery = await nsd.startDiscovery(
          labelPrinterServiceType,
          ipLookupType: nsd.IpLookupType.v4,
        );
        d.addListener(() {
          controller.add([
            for (final s in d.services) ?labelPrinterFromService(s),
          ]);
        });
        timer = Timer(timeout, () async {
          await stop();
          await controller.close();
        });
      } on Object catch (e, st) {
        controller.addError(e, st);
        await controller.close();
      }
    },
    onCancel: stop,
  );
  return controller.stream;
}
