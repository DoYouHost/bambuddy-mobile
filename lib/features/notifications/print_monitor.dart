import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/printer_status.dart';
import '../../core/notifications/notification_service.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../dashboard/ws_providers.dart';

/// Bazowe id alertów; do każdego dodajemy `printer_id`, by alerty różnych
/// drukarek się nie nadpisywały (id ongoing = 1 jest zarezerwowane).
const int _finishedAlertBase = 1000;
const int _failedAlertBase = 2000;

/// Zapamiętana faza drukarki między ramkami — do wykrycia przejścia
/// „drukuje → skończone/błąd" (alert odpalamy raz, na zboczu).
class _Phase {
  const _Phase({required this.printing});
  final bool printing;
}

/// Klucz throttlingu wiszącego powiadomienia: aktualizujemy je tylko, gdy
/// zmieni się drukarka, całkowity %, minuta ETA albo liczba aktywnych wydruków
/// — inaczej każda ramka WS przerysowywałaby notyfikację bez potrzeby.
class _OngoingKey {
  const _OngoingKey(this.printerId, this.percent, this.etaMinutes, this.count);
  final int printerId;
  final int percent;
  final int? etaMinutes;
  final int count;

  @override
  bool operator ==(Object other) =>
      other is _OngoingKey &&
      other.printerId == printerId &&
      other.percent == percent &&
      other.etaMinutes == etaMinutes &&
      other.count == count;

  @override
  int get hashCode => Object.hash(printerId, percent, etaMinutes, count);
}

/// Mózg powiadomień: obserwuje najnowsze statusy drukarek i steruje
/// [NotificationService] — wiszące powiadomienie podczas wydruku oraz alerty
/// na zakończenie/błąd. Czysta logika ([update]) jest testowalna z fake
/// serwisem; brak zależności od pluginu czy `BuildContext`.
class PrintMonitor {
  PrintMonitor(
    this._notifications, {
    AppLocalizations Function()? l10n,
    DateTime Function()? clock,
  })  : _l10n = l10n ?? _defaultL10n,
        _now = clock ?? DateTime.now;

  final NotificationService _notifications;
  final AppLocalizations Function() _l10n;
  final DateTime Function() _now;

  final Map<int, _Phase> _prev = {};
  _OngoingKey? _lastOngoing;

  /// Wywoływane na każdą zmianę mapy statusów (z `printerStatusesProvider`).
  void update(Map<int, PrinterStatus> statuses) {
    // 1) Alerty na zboczu „drukował → już nie".
    for (final entry in statuses.entries) {
      final id = entry.key;
      final status = entry.value;
      final wasPrinting = _prev[id]?.printing ?? false;
      final isPrinting = status.isPrinting;

      if (wasPrinting && !isPrinting) {
        switch (status.state?.toUpperCase()) {
          case 'FINISH':
          case 'FINISHED':
            _alertFinished(id, status);
          case 'FAILED':
            _alertFailed(id, status);
          // Inny/nieznany stan końcowy → bez fałszywego alertu, tylko sprzątamy.
        }
      }
      _prev[id] = _Phase(printing: isPrinting);
    }
    // Drukarki, które zniknęły z mapy: traktujemy jak nieaktywne (bez alertu).
    _prev.removeWhere((id, _) => !statuses.containsKey(id));

    // 2) Wiszące powiadomienie dla aktualnie drukujących.
    final printing = statuses.values.where((s) => s.isPrinting).toList()
      ..sort((a, b) => (a.remainingTime ?? 1 << 30)
          .compareTo(b.remainingTime ?? 1 << 30));

    if (printing.isEmpty) {
      if (_lastOngoing != null) {
        _lastOngoing = null;
        _notifications.clearOngoing();
      }
      return;
    }

    final lead = printing.first; // kończy się najwcześniej
    final percent = (lead.progress ?? 0).round().clamp(0, 100);
    final key = _OngoingKey(lead.id, percent, lead.remainingTime, printing.length);
    if (key == _lastOngoing) return; // nic istotnego się nie zmieniło
    _lastOngoing = key;

    final l = _l10n();
    final title = _jobName(lead) ?? lead.name ?? l.printersTitle;
    final eta = _etaClock(lead.remainingTime);
    var body = eta == null
        ? '$percent%'
        : l.notifOngoingBody(percent, eta);
    if (printing.length > 1) {
      body = '$body · ${l.notifMorePrints(printing.length - 1)}';
    }
    _notifications.showOngoing(title: title, body: body, progress: percent);
  }

  void _alertFinished(int id, PrinterStatus status) {
    final l = _l10n();
    final name = _jobName(status) ?? status.name ?? l.printersTitle;
    _notifications.showAlert(
      id: _finishedAlertBase + id,
      title: l.printFinishedTitle,
      body: l.printFinishedBody(name),
      payload: 'printer:$id',
    );
  }

  void _alertFailed(int id, PrinterStatus status) {
    final l = _l10n();
    final name = _jobName(status) ?? status.name ?? l.printersTitle;
    _notifications.showAlert(
      id: _failedAlertBase + id,
      title: l.printFailedTitle,
      body: l.printFailedBody(name),
      payload: 'printer:$id',
    );
  }

  String? _jobName(PrinterStatus s) {
    for (final candidate in [s.currentPrint, s.gcodeFile]) {
      final v = candidate?.trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  /// ETA jako konkretna godzina zakończenia (np. „21:20"), nie „za X".
  /// Gdy wydruk skończy się innego dnia, dokładamy datę „dd.MM 21:20".
  /// Format ręczny (24 h) — bez inicjalizacji intl, działa poza drzewem widgetów.
  String? _etaClock(int? minutes) {
    if (minutes == null) return null;
    final now = _now();
    final finish = now.add(Duration(minutes: minutes));
    final hh = finish.hour.toString().padLeft(2, '0');
    final mm = finish.minute.toString().padLeft(2, '0');
    final time = '$hh:$mm';
    final sameDay = finish.year == now.year &&
        finish.month == now.month &&
        finish.day == now.day;
    if (sameDay) return time;
    final dd = finish.day.toString().padLeft(2, '0');
    final mo = finish.month.toString().padLeft(2, '0');
    return '$dd.$mo $time';
  }
}

/// Locale systemu zawężone do wspieranych (en/pl) — `lookupAppLocalizations`
/// rzuca na nieobsługiwanym języku, a monitor działa poza drzewem widgetów.
AppLocalizations _defaultL10n() {
  final lang = PlatformDispatcher.instance.locale.languageCode;
  final locale = lang == 'pl' ? const Locale('pl') : const Locale('en');
  return lookupAppLocalizations(locale);
}

/// Żyje przez całą sesję (watchowany w korzeniu aplikacji), żeby łapać start
/// wydruku niezależnie od tego, który ekran jest zamontowany. Subskrypcja
/// `printerStatusesProvider` zarazem podtrzymuje klienta WS.
final printMonitorProvider = Provider<PrintMonitor>((ref) {
  final monitor = PrintMonitor(ref.watch(notificationServiceProvider));
  ref.listen<Map<int, PrinterStatus>>(
    printerStatusesProvider,
    (_, next) => monitor.update(next),
    fireImmediately: true,
  );
  return monitor;
});
