/// Watch↔phone RPC contract over the Wear Data Layer (`MessageClient`).
///
/// The watch sends a [WearRpcRequest]; the phone executes it and replies with a
/// [WearRpcResponse] carrying the raw server JSON, which the watch parses with
/// the existing model `fromJson`s — no `toJson` anywhere.
///
/// `watch_connectivity` hardcodes one MessageClient path for every message, so
/// requests and responses share a stream and are told apart by `kind` rather
/// than by Data Layer paths. Correlation is by `id`, and delivery is not
/// guaranteed — callers pair this with a timeout.
library;

import 'dart:math';

/// Actions the watch can ask the phone to relay to the bambuddy server.
enum WearRpcAction {
  /// Printers + statuses. Response `data`: `{"printers": [{"printer": {...},
  /// "status": {...}|absent}]}` — raw server JSON under both keys.
  getFleet,

  /// The connected server's version, for the watch's settings footer. Response
  /// `data`: `{"version": "1.2.6b1"}`, the key absent when the phone could not
  /// read one — and a phone older than this action never decodes the request at
  /// all, which the watch reads as unknown after its timeout.
  getServerVersion,
  pause,
  resume,
  stop,
  clearPlate,
  startNext,

  /// Clear the printer's active error dialog. No parameters beyond the printer.
  hmsClear,

  /// Run one remediation action for one fault: needs [WearRpcRequest.printError]
  /// and [WearRpcRequest.hmsAction], plus [WearRpcRequest.jobId] when the fault
  /// carried one.
  hmsAction,
}

/// What a *second* run of an action costs. Two places ask from opposite sides —
/// the watch about a timed-out call, the phone about a sender that stopped
/// waiting — and one table keeps their answers from drifting apart.
enum WearRpcRetry {
  /// A read: asking again changes nothing.
  read,

  /// A command whose second run leaves the printer where the first one already
  /// put it.
  idempotent,

  /// A command whose second run does something the first one did not.
  destructive,
}

extension WearRpcActionRetry on WearRpcAction {
  /// Exhaustive on purpose: a new action is classified here, in the protocol,
  /// rather than separately in each place that asks.
  WearRpcRetry get retry => switch (this) {
    WearRpcAction.getFleet => WearRpcRetry.read,
    WearRpcAction.getServerVersion => WearRpcRetry.read,
    WearRpcAction.pause => WearRpcRetry.idempotent,
    WearRpcAction.resume => WearRpcRetry.idempotent,
    WearRpcAction.stop => WearRpcRetry.idempotent,
    WearRpcAction.clearPlate => WearRpcRetry.idempotent,
    WearRpcAction.hmsClear => WearRpcRetry.idempotent,
    WearRpcAction.hmsAction => WearRpcRetry.idempotent,
    WearRpcAction.startNext => WearRpcRetry.destructive,
  };

  /// Whether the **watch** may serve this over its own REST connection after
  /// the relay timed out (`HybridWearTransport`).
  ///
  /// Only a read, [WearRpcRetry.idempotent] included: a timed-out command may
  /// have run with the reply lost on the way back, and the watch cannot tell
  /// that from a phone that never heard it. The user is owed one answer about
  /// one command, not two attempts at it.
  bool get mayRepeatOverRest => retry == WearRpcRetry.read;

  /// Whether the **phone** may execute this for a sender that has already
  /// given up on it (`wear_relay_engine.dart`).
  ///
  /// The phone is not guessing: it was woken *by* this request, so nothing has
  /// run yet. The only question left is what the user's next tap would do, and
  /// only [WearRpcRetry.destructive] answers "print the next plate as well".
  bool get isRepeatSafe => retry != WearRpcRetry.destructive;
}

const _kVersion = 'v';
const _kKind = 'kind';
const _kId = 'id';
const _kAction = 'action';
const _kPrinterId = 'printerId';
const _kPrintError = 'printError';
const _kHmsAction = 'hmsAction';
const _kJobId = 'jobId';
const _kOk = 'ok';
const _kState = 'state';
const _kData = 'data';
const _kError = 'error';
const _kReason = 'reason';

const _kindRequest = 'req';
const _kindResponse = 'res';
const _kindAck = 'ack';

/// Contract version, bumped on incompatible changes. A decoder seeing a newer
/// one still tries to parse, since fields are additive.
///
/// v2 = the sender understands [WearRpcAck] and waits [wearRpcWakeTimeout] once
/// acked. The phone reads it off a request to decide whether it may execute one
/// on the cold path at all: a v1 watch has already given up, and its retry would
/// run the command twice.
const wearRpcVersion = 2;

/// First version whose sender waits for a woken phone. Mirrored natively in
/// `WearRelayListenerService.kt` — the cold path is gated on it.
const wearRpcWakeAwareVersion = 2;

/// How long the watch waits for a request the phone acked as "waking": a cold
/// engine boot (process start, secure storage, an authenticated Dio) plus the
/// request. Deliberately not the timeout for a phone that never acks.
const wearRpcWakeTimeout = Duration(seconds: 15);

/// The one [WearRpcAck.state] there is so far: the phone was asleep, its relay
/// is starting, the reply will be late but it is coming. An unknown state
/// decodes as an ack all the same — any ack means "someone is on it".
const wearRpcAckWaking = 'waking';

final _rng = Random();

/// Correlation id: time-ordered, collision-safe enough for a single watch.
String _newRpcId() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
    '-${_rng.nextInt(1 << 32).toRadixString(36)}';

/// Deeply re-keys nested maps to `Map<String, dynamic>` and drops nulls. Needed
/// on both ends: the Data Layer rejects a null, and maps arriving over the
/// plugin's EventChannel are `Map<Object?, Object?>` below the top level — only
/// the outermost one is cast for us.
dynamic deepSanitize(dynamic value) => switch (value) {
  Map m => <String, dynamic>{
    for (final e in m.entries)
      if (e.value != null) '${e.key}': deepSanitize(e.value),
  },
  List l => [for (final v in l) deepSanitize(v)],
  _ => value,
};

/// Blank is how a value the sender did not have arrives over the bridge, and it
/// is never a valid code, action key or job id.
String? _stringOrNull(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;

/// Watch→phone request.
class WearRpcRequest {
  const WearRpcRequest({
    required this.id,
    required this.action,
    this.version = wearRpcVersion,
    this.printerId,
    this.printError,
    this.hmsAction,
    this.jobId,
  });

  /// New request with a fresh correlation id.
  WearRpcRequest.create(
    this.action, {
    this.printerId,
    this.printError,
    this.hmsAction,
    this.jobId,
  }) : id = _newRpcId(),
       version = wearRpcVersion;

  final String id;
  final WearRpcAction action;

  /// The *sender's* contract version, which is what tells the phone whether
  /// this watch will still be listening after a wake — see
  /// [wearRpcWakeAwareVersion].
  final int version;

  /// Required for every action except [WearRpcAction.getFleet] and
  /// [WearRpcAction.getServerVersion].
  final int? printerId;

  /// The fault's `full_code`, carried through untouched: the firmware matches
  /// HMS commands on it, and a code rebuilt anywhere along this path would be
  /// dropped by the printer without a word.
  final String? printError;

  /// The `HMSAction` key to run. Named apart from [action], which is the RPC's
  /// own verb — this one is the printer's.
  final String? hmsAction;

  /// The fault's `job_id` snapshot, absent for an idle-state fault.
  final String? jobId;

  /// Whether a phone woken *by this request* may execute it there and then.
  ///
  /// A sender older than [wearRpcWakeAwareVersion] gave up long before a cold
  /// boot can answer, so its user's next tap is the second run — which only a
  /// repeat-safe action survives. Later requests reach a warm engine and are not
  /// gated at all.
  bool get mayRunOnWake =>
      version >= wearRpcWakeAwareVersion || action.isRepeatSafe;

  Map<String, dynamic> encode() => <String, dynamic>{
    // The version this request carries, not the one this build speaks: they
    // differ the moment a decoded request is encoded again, and stamping the
    // current one would promote a v1 watch that stopped waiting into one the
    // phone may run a non-repeat-safe action for.
    _kVersion: version,
    _kKind: _kindRequest,
    _kId: id,
    _kAction: action.name,
    if (printerId != null) _kPrinterId: printerId,
    if (printError != null) _kPrintError: printError,
    if (hmsAction != null) _kHmsAction: hmsAction,
    if (jobId != null) _kJobId: jobId,
  };

  /// Returns null for foreign/malformed maps and for responses — the shared
  /// message stream carries both kinds, so decoders act as filters.
  static WearRpcRequest? decode(Map<Object?, Object?> map) {
    if (map[_kKind] != _kindRequest) return null;
    final id = map[_kId];
    if (id is! String || id.isEmpty) return null;
    // A newer watch talking to an older phone: it cannot execute what it does
    // not know, and the watch's timeout turns that silence into a fallback.
    final action = WearRpcAction.values.asNameMap()[map[_kAction]];
    if (action == null) return null;
    final printerId = map[_kPrinterId];
    final version = map[_kVersion];
    return WearRpcRequest(
      id: id,
      action: action,
      // Absent only in a map that never came from this app; 1 is the version
      // that did not send one it could be trusted for.
      version: version is int ? version : 1,
      printerId: printerId is int ? printerId : null,
      printError: _stringOrNull(map[_kPrintError]),
      hmsAction: _stringOrNull(map[_kHmsAction]),
      jobId: _stringOrNull(map[_kJobId]),
    );
  }
}

/// Phone→watch response, correlated to the request by [id].
class WearRpcResponse {
  const WearRpcResponse.ok(this.id, [this.data])
    : ok = true,
      error = null,
      reason = null;

  const WearRpcResponse.failure(this.id, this.error, {this.reason})
    : ok = false,
      data = null;

  final String id;
  final bool ok;

  /// Raw server-shaped JSON payload (shape depends on the action); null for
  /// failures and for command actions that return nothing.
  final Map<String, dynamic>? data;

  /// Short machine-readable reason (e.g. `phone-unconfigured`, `empty-queue`).
  final String? error;

  /// What the *server* said, when the failure came from it — the sentence naming
  /// the missing permission on a 403. Optional: an older phone relays without it
  /// and the watch falls back to wording derived from [error].
  final String? reason;

  Map<String, dynamic> encode() => <String, dynamic>{
    _kVersion: wearRpcVersion,
    _kKind: _kindResponse,
    _kId: id,
    _kOk: ok,
    if (data != null) _kData: deepSanitize(data),
    if (error != null) _kError: error,
    if (reason != null) _kReason: reason,
  };

  /// Returns null for foreign/malformed maps and for requests.
  static WearRpcResponse? decode(Map<Object?, Object?> map) {
    if (map[_kKind] != _kindResponse) return null;
    final id = map[_kId];
    if (id is! String || id.isEmpty) return null;
    if (map[_kOk] == true) {
      final raw = map[_kData];
      return WearRpcResponse.ok(
        id,
        raw is Map ? deepSanitize(raw) as Map<String, dynamic> : null,
      );
    }
    final error = map[_kError];
    final reason = map[_kReason];
    return WearRpcResponse.failure(
      id,
      error is String ? error : 'unknown',
      reason: reason is String && reason.isNotEmpty ? reason : null,
    );
  }
}

/// Phone→watch "hold on": the phone had no relay listening, the message woke
/// its process, and an answer to [id] is coming later than the watch's normal
/// deadline.
///
/// A separate `kind` rather than a field on [WearRpcResponse], because a watch
/// built before this existed must not read it as an answer: its decoders match
/// on the kind and drop everything else, so an ack is silently ignored there
/// and the request keeps the deadline it always had.
class WearRpcAck {
  const WearRpcAck(this.id, {this.state = wearRpcAckWaking});

  final String id;

  /// Why the answer is late; [wearRpcAckWaking] today.
  final String state;

  Map<String, dynamic> encode() => <String, dynamic>{
    _kVersion: wearRpcVersion,
    _kKind: _kindAck,
    _kId: id,
    _kState: state,
  };

  /// Returns null for foreign/malformed maps and for the other two kinds.
  static WearRpcAck? decode(Map<Object?, Object?> map) {
    if (map[_kKind] != _kindAck) return null;
    final id = map[_kId];
    if (id is! String || id.isEmpty) return null;
    return WearRpcAck(
      id,
      state: _stringOrNull(map[_kState]) ?? wearRpcAckWaking,
    );
  }
}
