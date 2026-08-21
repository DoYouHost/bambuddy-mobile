import 'dart:async';

import 'package:home_widget/home_widget.dart';

import '../../l10n/app_localizations.dart';
import '../models/printer_status.dart';
import 'widget_status.dart';
import '../notifications/hms_catalog.dart';

/// Snapshot of the fields that actually show up on the widget — mirrors
/// `_OngoingKey` in `print_monitor.dart`. Callers publish on every WS frame
/// and every poll tick; without this, an hours-long print would redo the
/// full 9x `saveWidgetData` + native broadcast (and a cover re-fetch check)
/// on every single frame even though nothing visible changed.
class WidgetPublishKey {
  const WidgetPublishKey({
    required this.printerId,
    required this.statusKey,
    required this.progressPct,
    required this.etaMinutes,
    required this.layers,
    required this.coverUrl,
  });

  final int? printerId;
  final String statusKey;
  final int progressPct;
  final int? etaMinutes;
  final String layers;
  final String? coverUrl;

  @override
  bool operator ==(Object other) =>
      other is WidgetPublishKey &&
      other.printerId == printerId &&
      other.statusKey == statusKey &&
      other.progressPct == progressPct &&
      other.etaMinutes == etaMinutes &&
      other.layers == layers &&
      other.coverUrl == coverUrl;

  @override
  int get hashCode => Object.hash(
        printerId,
        statusKey,
        progressPct,
        etaMinutes,
        layers,
        coverUrl,
      );
}

/// Publishes the state of one selected printer to the native home screen widget
/// (`BambuddyWidgetProvider`). Fed from TWO sources: the UI provider in the foreground
/// ([printerStatusesProvider]) and the background isolate (foreground service). Both call
/// [publish] on every fresh frame — `home_widget` writes data to shared SharedPreferences
/// and updates the widget.
///
/// Intentionally simple: the widget shows ONE printer (prefers one actively printing;
/// otherwise, the first by `id`). Dynamic data (names, status label) are already localized
/// from Dart — the native side doesn't translate them, only handles layout and
/// the status dot color (by `status_key`).
class HomeWidgetPublisher {
  /// Name of the [AppWidgetProvider] class on the Android side (package inferred from
  /// applicationId). `home_widget` uses it for `updateWidget`.
  static const String _androidProvider = 'BambuddyWidgetProvider';

  /// Status keys — must match color map in Kotlin.

  /// Last published key — static, so naturally per-isolate (foreground UI and
  /// background service each have their own Dart heap and never share this).
  static WidgetPublishKey? _lastKey;

  /// Whether a publish is currently writing to `home_widget` storage.
  static bool _publishing = false;

  /// Computes the [WidgetPublishKey] for the printer [publish] would pick —
  /// exposed so callers can also use it, though [publish] already no-ops
  /// when nothing changed.
  static WidgetPublishKey keyFor(
    Map<int, PrinterStatus> statuses, {
    String? Function(HmsError)? describeHms,
  }) {
    final picked = _select(statuses);
    if (picked == null) {
      return const WidgetPublishKey(
        printerId: null,
        statusKey: WidgetStatus.offline,
        progressPct: 0,
        etaMinutes: null,
        layers: '',
        coverUrl: null,
      );
    }
    final baseKey = WidgetStatus.keyFor(picked);
    // An offline printer can't be actively faulting — its `hms_errors` are just
    // the last-known values carried forward by mergedWith. Keep OFFLINE, don't
    // flip the widget to an error state. Parity with the notification path.
    final hms = baseKey == WidgetStatus.offline
        ? null
        : _topHmsError(picked, describeHms);
    final key = hms != null ? WidgetStatus.error : baseKey;
    final printing = WidgetStatus.isActive(key);
    return WidgetPublishKey(
      printerId: picked.id,
      statusKey: key,
      progressPct: WidgetStatus.progressPct(picked),
      etaMinutes: printing ? picked.remainingTime : null,
      layers: _layers(picked, baseKey),
      coverUrl: picked.coverUrl,
    );
  }

  /// Saves the selected printer's state and updates the widget. Safe to call frequently —
  /// no-ops when nothing meaningful changed since the last call ([WidgetPublishKey]),
  /// and drops the request outright if a publish is already writing (the isolate's next
  /// frame will retry — a slow `fetchCover` completing after a newer publish must not
  /// overwrite it with a stale `cover_path`).
  ///
  /// [describeHms] — HMS error description from catalog (foreground: `HmsCatalog.instance`,
  /// background: isolate's local catalog). [fetchCover] — fetches print cover to file
  /// (authenticated with camera token); differs per isolate, so injected.
  /// Both optional — without them, widget simply skips HMS error/thumbnail.
  static Future<void> publish(
    Map<int, PrinterStatus> statuses,
    AppLocalizations l10n, {
    String? Function(HmsError)? describeHms,
    Future<String?> Function(PrinterStatus picked)? fetchCover,
    void Function()? resetCover,
  }) async {
    final key = keyFor(statuses, describeHms: describeHms);
    if (key == _lastKey || _publishing) return;

    _publishing = true;
    try {
      await _doPublish(
        statuses,
        l10n,
        describeHms: describeHms,
        fetchCover: fetchCover,
        resetCover: resetCover,
      );
      _lastKey = key;
    } finally {
      _publishing = false;
    }
  }

  static Future<void> _doPublish(
    Map<int, PrinterStatus> statuses,
    AppLocalizations l10n, {
    String? Function(HmsError)? describeHms,
    Future<String?> Function(PrinterStatus picked)? fetchCover,
    void Function()? resetCover,
  }) async {
    final picked = _select(statuses);

    if (picked == null) {
      // Nothing to show a cover for — drop the cache so the next print
      // (even one reusing the same `cover_url` the server exposed before)
      // re-fetches instead of short-circuiting to this stale bitmap.
      resetCover?.call();
      await HomeWidget.saveWidgetData<String>('status_key', WidgetStatus.offline);
      await HomeWidget.saveWidgetData<String>(
          'printer_name', l10n.widgetNoPrinter);
      await HomeWidget.saveWidgetData<String>('print_name', '');
      await HomeWidget.saveWidgetData<String>(
          'status_label', l10n.statusUnavailable);
      await HomeWidget.saveWidgetData<String>('error_text', '');
      await HomeWidget.saveWidgetData<String>('eta', '');
      await HomeWidget.saveWidgetData<String>('layers', '');
      await HomeWidget.saveWidgetData<String>('cover_path', '');
      await HomeWidget.saveWidgetData<int>('progress', 0);
      await HomeWidget.saveWidgetData<bool>('printing', false);
    } else {
      final baseKey = WidgetStatus.keyFor(picked);
      final printing = WidgetStatus.isActive(baseKey);

      // Active HMS error overrides status (red dot + error content),
      // but we still show progress/ETA if the printer is printing anyway.
      // Skip when offline — stale carried-forward errors must not mask OFFLINE.
      final hms = baseKey == WidgetStatus.offline
        ? null
        : _topHmsError(picked, describeHms);
      final key = hms != null ? WidgetStatus.error : baseKey;
      // Chip is a short badge — the full HMS sentence goes to `error_text` (the
      // body, which wraps), NOT the chip, or it overflows the widget's edge.
      final statusLabel =
          hms != null ? l10n.widgetStatusError : WidgetStatus.label(l10n, key);
      final errorText = hms != null
          ? hmsHumanText(hms, description: describeHms?.call(hms))
          : '';

      await HomeWidget.saveWidgetData<String>('status_key', key);
      await HomeWidget.saveWidgetData<String>(
          'printer_name', picked.name ?? l10n.widgetNoPrinter);
      await HomeWidget.saveWidgetData<String>(
          'print_name', _printName(picked, l10n, baseKey));
      await HomeWidget.saveWidgetData<String>('status_label', statusLabel);
      await HomeWidget.saveWidgetData<String>('error_text', errorText);
      await HomeWidget.saveWidgetData<String>(
          'eta', _eta(picked, l10n, baseKey));
      await HomeWidget.saveWidgetData<String>('layers', _layers(picked, baseKey));
      await HomeWidget.saveWidgetData<int>(
          'progress', WidgetStatus.progressPct(picked));
      await HomeWidget.saveWidgetData<bool>('printing', printing);

      // Fetch cover only during printing and only if server provides `cover_url`.
      // Skip during calibration phases (`auto_cali_*`) — those have no cover,
      // so otherwise the widget would show the previous print's thumbnail.
      var coverPath = '';
      if (printing && picked.coverUrl != null && !picked.isCalibration) {
        if (fetchCover != null) coverPath = await fetchCover(picked) ?? '';
      } else {
        // Print ended (or no cover this phase) — drop the cache so a LATER
        // print reusing the same `cover_url` (server exposes a stable
        // "current print" path, not one keyed by job) doesn't short-circuit
        // to this now-outdated bitmap.
        resetCover?.call();
      }
      await HomeWidget.saveWidgetData<String>('cover_path', coverPath);
    }

    await HomeWidget.updateWidget(
      androidName: _androidProvider,
      qualifiedAndroidName:
          'page.codeberg.morganmlgman.bambuddy_mobile.$_androidProvider',
    );
  }

  /// The first "displayable" HMS error (severity 1..4 / with content — see
  /// [hmsIsDisplayable]), or `null`. Same criteria as the printer card.
  static HmsError? _topHmsError(
    PrinterStatus s,
    String? Function(HmsError)? describeHms,
  ) {
    for (final e in s.hmsErrors ?? const <HmsError>[]) {
      if (hmsIsDisplayable(e, description: describeHms?.call(e))) return e;
    }
    return null;
  }

  /// Layers as "X/Y" during printing, if server provides both fields. Otherwise empty.
  static String _layers(PrinterStatus s, String key) {
    if (key != WidgetStatus.printing && key != WidgetStatus.paused) return '';
    final cur = s.layerNum;
    final total = s.totalLayers;
    if (cur == null || total == null || total <= 0) return '';
    return '$cur/$total';
  }

  /// Selects printer to show: first one actively printing (connected),
  /// otherwise the first by ascending `id`. null if no printers.
  static PrinterStatus? _select(Map<int, PrinterStatus> statuses) {
    if (statuses.isEmpty) return null;
    final sorted = statuses.values.toList()..sort((a, b) => a.id.compareTo(b.id));
    for (final s in sorted) {
      if ((s.connected ?? false) && s.isPrinting) return s;
    }
    return sorted.first;
  }

  /// Print name to show: when printing — current file (or stage if progress not yet available);
  /// when not printing — empty (UI hides the row).
  static String _printName(
    PrinterStatus s,
    AppLocalizations l10n,
    String key,
  ) {
    if (key != WidgetStatus.printing && key != WidgetStatus.paused) return '';
    final name = s.currentPrint ?? s.gcodeFile;
    if (name != null && name.trim().isNotEmpty) return name.trim();
    // Prep phase without file name — show stage if server provides it.
    return s.stgCurName?.trim() ?? '';
  }

  /// ETA row: remaining time + finish time (HH:mm). Empty outside printing or if
  /// server doesn't provide remaining time. Format matches the printer card
  /// (`durationMinutes`/`durationHoursMinutes`).
  static String _eta(PrinterStatus s, AppLocalizations l10n, String key) {
    if (key != WidgetStatus.printing && key != WidgetStatus.paused) return '';
    final mins = s.remainingTime ?? 0;
    if (mins <= 0) return '';
    final dur = mins < 60
        ? l10n.durationMinutes(mins)
        : l10n.durationHoursMinutes(mins ~/ 60, mins % 60);
    final at = DateTime.now().add(Duration(minutes: mins));
    final hh = at.hour.toString().padLeft(2, '0');
    final mm = at.minute.toString().padLeft(2, '0');
    return '$dur · $hh:$mm';
  }

}
