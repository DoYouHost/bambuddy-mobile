import 'dart:async';

import '../api/api_exceptions.dart';
import '../models/printer.dart';

/// Which location each printer is in, for the alarm's location exclusions in
/// the background isolate. Status frames do not carry it; `GET /printers` does.
///
/// Answers from what it has and never waits: the alarm is decided on the frame.
/// A printer it does not know yet — the list not loaded, the call refused, a
/// printer added since — answers null, which excludes nothing, and asks for the
/// list again so the next alarm knows.
class PrinterLocations {
  PrinterLocations(this._fetch);

  final Future<List<Printer>> Function() _fetch;
  final Map<int, String?> _byPrinter = {};
  Future<void>? _loading;

  String? of(int printerId) {
    if (!_byPrinter.containsKey(printerId)) unawaited(load());
    return _byPrinter[printerId];
  }

  /// One request at a time. A refusal from the server leaves the map as it
  /// was; anything else is a bug and is rethrown.
  Future<void> load() => _loading ??= () async {
    try {
      final printers = await _fetch();
      _byPrinter
        ..clear()
        ..addAll({
          for (final p in printers)
            p.id: (p.location?.isEmpty ?? true) ? null : p.location,
        });
    } on AppApiException {
      // Unknown stays unknown: the alarm rings, as for any printer not listed.
    } finally {
      _loading = null;
    }
  }();
}
