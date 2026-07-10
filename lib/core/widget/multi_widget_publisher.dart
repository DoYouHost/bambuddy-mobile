import 'package:home_widget/home_widget.dart';

import '../../l10n/app_localizations.dart';
import '../models/printer_status.dart';

/// Publishes the whole fleet to the native multi-printer widget
/// ([BambuddyMultiWidgetProvider]). Fed from the same two sources as
/// [HomeWidgetPublisher] (foreground provider + background isolate): both call
/// [publish] on every fresh frame. All labels are localized here — the native
/// side only maps status keys to colors and lays views out.
///
/// Writes into the shared `home_widget` store under a `multi_` namespace, so it
/// never clashes with the single-printer widget's keys.
class MultiWidgetPublisher {
  static const String _androidProvider = 'BambuddyMultiWidgetProvider';

  /// How many printer rows the list layout renders (must match MAX_ROWS in Kotlin).
  static const int _maxRows = 3;

  static const String _kPrinting = 'printing';
  static const String _kPaused = 'paused';
  static const String _kFinished = 'finished';
  static const String _kFailed = 'failed';
  static const String _kIdle = 'idle';
  static const String _kOffline = 'offline';

  /// Last published signature — per-isolate (static, separate Dart heaps).
  static String? _lastSig;
  static bool _publishing = false;

  /// Saves the fleet state and updates the multi widget. Safe to call often —
  /// no-ops when nothing visible changed, and drops the call if one is in flight.
  static Future<void> publish(
    Map<int, PrinterStatus> statuses,
    AppLocalizations l10n,
  ) async {
    final sig = _signature(statuses);
    if (sig == _lastSig || _publishing) return;

    _publishing = true;
    try {
      await _doPublish(statuses, l10n);
      _lastSig = sig;
    } finally {
      _publishing = false;
    }
  }

  static Future<void> _doPublish(
    Map<int, PrinterStatus> statuses,
    AppLocalizations l10n,
  ) async {
    final ranked = _ranked(statuses);
    final total = ranked.length;
    final printing =
        ranked.where((s) => _isActive(_statusKey(s))).length;
    final offline = ranked.where((s) => _statusKey(s) == _kOffline).length;
    final idle = total - printing - offline;

    await HomeWidget.saveWidgetData<String>('multi_title', l10n.widgetMultiTitle);
    await HomeWidget.saveWidgetData<String>(
        'multi_count', l10n.widgetMultiActive(printing, total));
    await HomeWidget.saveWidgetData<int>('multi_printing', printing);
    await HomeWidget.saveWidgetData<int>('multi_total', total);
    await HomeWidget.saveWidgetData<String>(
        'multi_gauge_label', l10n.widgetMultiGaugeLabel);
    await HomeWidget.saveWidgetData<String>(
        'multi_idle_label', idle > 0 ? l10n.widgetMultiIdleCount(idle) : '');
    await HomeWidget.saveWidgetData<String>('multi_offline_label',
        offline > 0 ? l10n.widgetMultiOfflineCount(offline) : '');

    final shown = ranked.take(_maxRows).toList();
    final extra = total - shown.length;
    await HomeWidget.saveWidgetData<String>(
        'multi_more', extra > 0 ? l10n.widgetMultiMore(extra) : '');

    for (var i = 0; i < _maxRows; i++) {
      if (i < shown.length) {
        final s = shown[i];
        final key = _statusKey(s);
        final active = _isActive(key);
        await HomeWidget.saveWidgetData<String>(
            'multi_name_$i', s.name ?? l10n.widgetNoPrinter);
        await HomeWidget.saveWidgetData<String>('multi_status_$i', key);
        await HomeWidget.saveWidgetData<String>(
            'multi_sub_$i', _sub(s, l10n, key));
        await HomeWidget.saveWidgetData<int>(
            'multi_pct_$i', active ? _progressPct(s) : -1);
      } else {
        // Clear leftover slots so a shrinking roster doesn't show stale rows.
        await HomeWidget.saveWidgetData<String>('multi_name_$i', '');
        await HomeWidget.saveWidgetData<String>('multi_sub_$i', '');
        await HomeWidget.saveWidgetData<int>('multi_pct_$i', -1);
      }
    }

    await HomeWidget.updateWidget(
      androidName: _androidProvider,
      qualifiedAndroidName:
          'page.codeberg.morganmlgman.bambuddy_mobile.$_androidProvider',
    );
  }

  /// Printers ordered for display: active first, then idle-ish, then offline;
  /// within each group by ascending `id` (stable).
  static List<PrinterStatus> _ranked(Map<int, PrinterStatus> statuses) {
    final list = statuses.values.toList()
      ..sort((a, b) {
        final ra = _rank(_statusKey(a));
        final rb = _rank(_statusKey(b));
        if (ra != rb) return ra.compareTo(rb);
        return a.id.compareTo(b.id);
      });
    return list;
  }

  static int _rank(String key) {
    if (_isActive(key)) return 0;
    if (key == _kOffline) return 2;
    return 1;
  }

  static bool _isActive(String key) => key == _kPrinting || key == _kPaused;

  /// Sub-label: the print file name while active, otherwise the status word.
  static String _sub(PrinterStatus s, AppLocalizations l10n, String key) {
    if (_isActive(key)) {
      final name = (s.currentPrint ?? s.gcodeFile)?.trim();
      if (name != null && name.isNotEmpty) return name;
      return s.stgCurName?.trim() ?? '';
    }
    return _statusLabel(l10n, key);
  }

  /// A compact signature of everything the widget shows — to skip no-op publishes.
  static String _signature(Map<int, PrinterStatus> statuses) {
    final ranked = _ranked(statuses);
    return ranked
        .map((s) => '${s.id}:${_statusKey(s)}:${_progressPct(s)}:'
            '${(s.currentPrint ?? s.gcodeFile)?.trim() ?? ''}')
        .join('|');
  }

  static String _statusKey(PrinterStatus s) {
    if (!(s.connected ?? false)) return _kOffline;
    if (s.isPaused) return _kPaused;
    if (s.isPrinting) return _kPrinting;
    switch (s.state?.toUpperCase()) {
      case 'FINISH':
      case 'FINISHED':
        return _kFinished;
      case 'FAILED':
        return _kFailed;
    }
    return _kIdle;
  }

  static String _statusLabel(AppLocalizations l10n, String key) {
    switch (key) {
      case _kPrinting:
        return l10n.widgetStatusPrinting;
      case _kPaused:
        return l10n.widgetStatusPaused;
      case _kFinished:
        return l10n.widgetStatusFinished;
      case _kFailed:
        return l10n.widgetStatusFailed;
      case _kOffline:
        return l10n.widgetStatusOffline;
      default:
        return l10n.widgetStatusIdle;
    }
  }

  static int _progressPct(PrinterStatus s) {
    final p = s.progress ?? 0;
    final pct = p <= 1 ? (p * 100).round() : p.round();
    return pct.clamp(0, 100);
  }
}
