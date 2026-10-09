/// The label print server (https://github.com/DoYouHost/brother-ql-print-server)
/// — a separate LAN service, not part of bambuddy: no authentication, no
/// `/api/v1` prefix, and its own errors.
library;

import 'spool_label.dart';

/// Port the server listens on unless `LABEL_PRINTER_PORT` says otherwise.
const labelPrinterDefaultPort = 8000;

/// `GET /info`.
class LabelPrinterInfo {
  const LabelPrinterInfo({
    required this.model,
    required this.connected,
    required this.labelId,
    required this.maxCopies,
  });

  factory LabelPrinterInfo.fromJson(Map<String, dynamic> json) {
    final printer = json['printer'];
    final label = json['label'];
    final limits = json['limits'];
    return LabelPrinterInfo(
      model: printer is Map ? printer['model'] as String? : null,
      // Null on the wire for network and libusb printers, which cannot be
      // probed — "unknown", not "disconnected".
      connected: printer is Map ? printer['connected'] as bool? : null,
      labelId: label is Map ? label['id'] as String? : null,
      maxCopies: limits is Map ? (limits['max_copies'] as num?)?.toInt() : null,
    );
  }

  /// Whether [json] came from a label print server rather than any other HTTP
  /// service that happens to answer `/info` on that port.
  static bool isLabelPrinter(Object? json) =>
      json is Map && json['service'] == 'label-printer';

  final String? model;

  /// Null when the server cannot tell.
  final bool? connected;

  /// The loaded stock, e.g. `62x29`.
  final String? labelId;

  final int? maxCopies;

  /// Whether a [template] is drawn for the stock that is loaded. The server
  /// refuses (`wrong_format`) anything with other proportions, so this is what
  /// the app defaults to the label printer on — a choice the user can still
  /// make by hand.
  bool takes(SpoolLabelTemplate template) =>
      template.printerStock != null && template.printerStock == labelId;

  /// Whether any spool label template fits the loaded stock.
  bool get takesAnySpoolLabel => SpoolLabelTemplate.values.any(takes);
}

/// A label print server address as the user typed it, made into a base URL:
/// `http` when no scheme is given, [labelPrinterDefaultPort] when no port is,
/// no trailing slash. Empty or unparsable input gives an empty string.
///
/// Not [ServerProfile.normalizeBaseUrl]: that one strips `/api/v1` and leaves
/// the port alone, so a bare IP would land on port 80.
String normalizeLabelPrinterUrl(String raw) {
  var text = raw.trim();
  if (text.isEmpty) return '';
  if (!text.startsWith('http://') && !text.startsWith('https://')) {
    text = 'http://$text';
  }
  final uri = Uri.tryParse(text);
  if (uri == null || uri.host.isEmpty) return '';
  // `hasPort` is false for an explicit default (":80"), which still means what
  // the user typed — only a missing port gets the server's own.
  final hasExplicitPort = RegExp(
    r':\d+(/|$)',
  ).hasMatch(text.substring(text.indexOf('//') + 2));
  final port = hasExplicitPort ? uri.port : labelPrinterDefaultPort;
  // Built by hand: `Uri.toString` drops a port that is the scheme's default,
  // which would silently turn an explicit ":80" into "no port".
  final host = uri.host.contains(':') ? '[${uri.host}]' : uri.host;
  return '${uri.scheme}://$host:$port';
}
