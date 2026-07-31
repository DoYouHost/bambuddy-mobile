import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'log_event.dart';

/// The two envelope fields the relay wants beside the log: the session header it
/// renders into the issue, and which record schema the log follows.
///
/// Derived from the log rather than passed alongside it, because they are
/// properties *of* the log. Handing them to the sender separately would let a
/// caller describe one recording while attaching another, and the mismatch would
/// only ever surface as a public issue whose header contradicts its own log.
@immutable
class ReportEnvelope {
  const ReportEnvelope({required this.header, required this.logSchema});

  final Map<String, Object> header;
  final int logSchema;
}

/// The schema this build writes, and the number sent when a log does not say.
///
/// The same value the log carries as `v`, and it has to stay that way: the relay
/// accepts a fixed window of schemas and refuses everything outside it. Bumping
/// [LogHeader.formatVersion] therefore means registering the new version in the
/// relay's validators *before* a build that sends it reaches anybody.
const reportLogSchema = LogHeader.formatVersion;

/// Reads the envelope off the log's own first line.
///
/// Read back out of the log rather than rebuilt from `SessionFacts` for two
/// reasons: a session recovered from disk after a crash no longer has the facts,
/// and what the issue shows can then never disagree with what the log contains.
///
/// A log with no readable header yields an empty header and the current schema.
/// That is deliberate — the relay accepts an empty header, and a report without
/// one still beats no report at all.
ReportEnvelope reportEnvelope(String log) {
  final fields = _headerFields(log);
  return ReportEnvelope(
    header: _wireHeader(fields),
    // The log's own version, not this build's: a recording made before an update
    // still follows the schema it was written with, and it is the relay's job to
    // decide whether that one is still accepted.
    logSchema: switch (fields['v']) {
      final int v when v >= 1 => v,
      _ => reportLogSchema,
    },
  );
}

/// The header line as a raw map, or empty when the log does not start with one.
///
/// Same rule as [LogHeader.tryParse] for telling a header from a record: every
/// record carries `t`, no header does. A file whose header write failed silently
/// starts with a record, and reading that as a session header would put a single
/// event's fields in the issue as though they described the whole recording.
Map<String, Object?> _headerFields(String log) {
  final end = log.indexOf('\n');
  final line = end == -1 ? log : log.substring(0, end);
  if (line.isEmpty) return const {};

  final Object? decoded;
  try {
    decoded = jsonDecode(line);
  } on FormatException {
    return const {};
  }
  if (decoded is! Map<String, Object?>) return const {};
  return decoded.containsKey('t') ? const {} : decoded;
}

/// Passes the header through as the log wrote it.
///
/// Deliberately not filtered, trimmed or otherwise made to fit. The relay has its
/// own validation — key shape, scalars only, value and envelope sizes — and it is
/// the authority. Quietly reshaping the header here would mean the client
/// silently repairing headers the app should not be producing in the first place:
/// the header is assembled by us, so anything the relay refuses is our bug, and
/// it should fail loudly in testing rather than be papered over in the field.
///
/// Nulls are the one exception, and for typing rather than policy: the map has to
/// hold non-nullable values, and [LogHeader.toJson] omits empty fields anyway, so
/// a null here could only come from a hand-written file.
Map<String, Object> _wireHeader(Map<String, Object?> fields) => {
      for (final entry in fields.entries)
        if (entry.value case final Object value) entry.key: value,
    };
