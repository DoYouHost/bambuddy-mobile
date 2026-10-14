import '../format/datetime_format.dart';
import '../models/printer_status.dart';
import '../../l10n/app_localizations.dart';

/// What the ongoing print notification says: the phone's foreground service and
/// the watch's Ongoing Activity both show it, and have to pick the same printer
/// and call it the same thing (docs/notification-rules.md, "The ongoing notification").
class OngoingText {
  const OngoingText({
    required this.lead,
    required this.title,
    required this.body,
    required this.progress,
  });

  /// The printer that finishes first; the bar and the ETA are its own.
  final PrinterStatus lead;
  final String title;
  final String body;

  /// Null while the lead is preparing: its zero percent is not progress.
  final int? progress;
}

/// The printers still running, earliest finish first.
List<PrinterStatus> runningByEta(Iterable<PrinterStatus> statuses) =>
    statuses.where((s) => s.isPrinting).toList()
      ..sort((a, b) => a.etaRank.compareTo(b.etaRank));

/// Null when nothing is running. [printing] comes from [runningByEta].
OngoingText? ongoingText(
  List<PrinterStatus> printing,
  AppLocalizations l,
  DateTimeFormats formats,
  DateTime now,
) {
  if (printing.isEmpty) return null;
  final lead = printing.first;
  final percent = (lead.progress ?? 0).round().clamp(0, 100);
  final eta = _etaText(lead, l, formats, now);
  final String title;
  final String body;
  if (printing.length == 1) {
    // The job is what the user is waiting for; the machine needs no saying.
    title = jobLabel(lead, l);
    body = eta == null ? '$percent%' : l.notifOngoingBody(percent, eta);
  } else {
    title = l.printingCount(printing.length);
    final name = printerLabel(lead, l);
    final line = eta == null
        ? l.notifOngoingMultiBodyNoEta(name, percent)
        : l.notifOngoingMultiBody(name, percent, eta);
    body = '${l.nextAvailableLabel}$line';
  }
  return OngoingText(
    lead: lead,
    title: title,
    body: body,
    progress: lead.isPreparing ? null : percent,
  );
}

/// What goes after "ETA", or null for none; branches in the order of
/// [PrinterStatus.etaRank].
String? _etaText(
  PrinterStatus s,
  AppLocalizations l,
  DateTimeFormats formats,
  DateTime now,
) {
  final minutes = s.remainingTime;
  if (minutes == null) return null;
  if (minutes > 0) {
    return formats.clockOnDay(now.add(Duration(minutes: minutes)), now: now);
  }
  return s.isPreparing ? null : l.notifEtaSoon;
}

/// The job name, falling back to the printer name.
String jobLabel(PrinterStatus s, AppLocalizations l) =>
    _jobName(s) ?? s.name ?? l.printersTitle;

/// Not `s.name ?? …`: a printer named "  " would leave a gap between two
/// separators.
String printerLabel(PrinterStatus s, AppLocalizations l) =>
    (s.name?.trim().isNotEmpty ?? false) ? s.name! : l.printersTitle;

String? _jobName(PrinterStatus s) {
  for (final candidate in [s.currentPrint, s.gcodeFile]) {
    final v = candidate?.trim();
    if (v != null && v.isNotEmpty) return v;
  }
  return null;
}
