import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'relay_client.dart';

/// A report the user has already committed to sending, waiting for its ticket to
/// mature.
@immutable
class PendingReport {
  const PendingReport({
    required this.id,
    required this.description,
    required this.header,
    required this.logSchema,
    required this.ticket,
    required this.logPath,
  });

  final String id;
  final String description;
  final Map<String, Object> header;
  final int logSchema;
  final RelayTicket ticket;
  final String logPath;

  Map<String, dynamic> toJson() => {
        'id': id,
        'description': description,
        'header': header,
        'logSchema': logSchema,
        'ticket': ticket.toJson(),
        'logPath': logPath,
      };

  static PendingReport fromJson(Map<String, dynamic> json) => PendingReport(
        id: json['id'] as String,
        description: json['description'] as String,
        header: (json['header'] as Map).cast<String, Object>(),
        logSchema: json['logSchema'] as int,
        ticket:
            RelayTicket.fromJson((json['ticket'] as Map).cast<String, dynamic>()),
        logPath: json['logPath'] as String,
      );
}

/// Survives the app being closed while a report waits out its not-before delay.
///
/// The escalating wait can reach several minutes, and a user who tapped send is
/// entitled to assume the report is on its way — losing it because they switched
/// apps would make the delay feel like a failure rather than a queue. So the
/// whole report, log included, goes to disk the moment they commit to sending.
///
/// One slot, deliberately. A second report cannot be sent before the first one
/// clears anyway, and a queue that can grow is a queue that can hold a stale log
/// nobody remembers writing.
class ReportOutbox {
  /// [root] is injected by tests; production reads the app support directory.
  const ReportOutbox({this._root});

  final Directory? _root;

  Future<Directory> _dir() async {
    final base = _root ?? await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/outbox');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _slot() async => File('${(await _dir()).path}/pending.json');

  /// Writes the log beside the metadata rather than inside it: a recording can
  /// be twenty megabytes, which has no business in a JSON blob that gets parsed
  /// on every read.
  Future<PendingReport> put({
    required String id,
    required String description,
    required Map<String, Object> header,
    required int logSchema,
    required RelayTicket ticket,
    required String log,
  }) async {
    final dir = await _dir();
    final logFile = File('${dir.path}/$id.jsonl');
    await logFile.writeAsString(log, flush: true);

    final report = PendingReport(
      id: id,
      description: description,
      header: header,
      logSchema: logSchema,
      ticket: ticket,
      logPath: logFile.path,
    );
    await (await _slot()).writeAsString(jsonEncode(report.toJson()), flush: true);
    return report;
  }

  Future<PendingReport?> peek() async {
    final slot = await _slot();
    if (!slot.existsSync()) return null;
    try {
      final report = PendingReport.fromJson(
        (jsonDecode(await slot.readAsString()) as Map).cast<String, dynamic>(),
      );
      // A slot pointing at a log that is gone is worse than an empty one: it
      // would fail on every retry forever.
      if (!File(report.logPath).existsSync()) {
        await clear();
        return null;
      }
      return report;
    } on FormatException {
      // Half-written by a process that died mid-save. Nothing to recover.
      await clear();
      return null;
    }
  }

  Future<String?> readLog(PendingReport report) async {
    final file = File(report.logPath);
    return file.existsSync() ? await file.readAsString() : null;
  }

  Future<void> clear() async {
    final dir = await _dir();
    if (!dir.existsSync()) return;
    for (final entry in dir.listSync()) {
      if (entry is File) await entry.delete();
    }
  }
}
