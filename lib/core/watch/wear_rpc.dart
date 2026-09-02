/// Watch↔phone RPC contract over the Wear Data Layer (`MessageClient`).
///
/// The watch sends a [WearRpcRequest]; the phone executes it against the
/// server (or its live WS state) and replies with a [WearRpcResponse] carrying
/// the raw server JSON. The watch parses that JSON with the existing model
/// `fromJson`s, so no `toJson` is needed anywhere.
///
/// The `watch_connectivity` plugin hardcodes a single MessageClient path for
/// all messages, so requests and responses share one stream and are
/// discriminated by the `kind` field instead of Data Layer paths. Correlation
/// is by `id` (many requests may be in flight; delivery is not guaranteed —
/// callers pair this with a timeout).
library;

import 'dart:math';

/// Actions the watch can ask the phone to relay to the bambuddy server.
enum WearRpcAction {
  /// Printers + statuses. Response `data`: `{"printers": [{"printer": {...},
  /// "status": {...}|absent}]}` — raw server JSON under both keys.
  getFleet,
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

/// Whether running an action twice has the same effect as running it once.
///
/// One caller: a request from a watch too old to wait for a woken phone
/// ([wearRpcWakeAwareVersion]) has already timed out by the time the engine
/// could answer it, so the user's retry is the second run. Pausing a paused
/// printer or clearing a clear plate costs nothing; starting the next plate
/// twice prints it twice.
///
/// The switch is exhaustive on purpose — a new action cannot slip through as
/// "safe" by default.
extension WearRpcActionRepeat on WearRpcAction {
  bool get isRepeatSafe => switch (this) {
        WearRpcAction.getFleet => true,
        WearRpcAction.pause => true,
        WearRpcAction.resume => true,
        WearRpcAction.stop => true,
        WearRpcAction.clearPlate => true,
        WearRpcAction.hmsClear => true,
        WearRpcAction.hmsAction => true,
        WearRpcAction.startNext => false,
      };
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
/// version than it knows still tries to parse (fields are additive) — the
/// field exists so a future breaking change can be detected explicitly.
///
/// v2 = the sender understands [WearRpcAck] and waits [wearRpcWakeTimeout] for
/// a request it has been acked. The phone reads this off a request to decide
/// whether it may execute one on the cold path at all: a v1 watch has already
/// given up by then, and its retry would run the command a second time.
const wearRpcVersion = 2;

/// First version whose sender waits for a woken phone. Mirrored natively in
/// `WearRelayListenerService.kt` — the cold path is gated on it.
const wearRpcWakeAwareVersion = 2;

/// How long the watch waits for a request the phone acked as "waking". Covers a
/// cold engine boot (process start, secure storage, an authenticated Dio) plus
/// the request itself, and is deliberately not the timeout for a phone that
/// never acks — see [wearRpcAckWaking].
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

/// Deeply re-keys nested maps to `Map<String, dynamic>` and drops null values.
/// Needed on both ends: raw server JSON carries nulls (the Data Layer map
/// serialization rejects them, same as the config codec), and maps arriving
/// over the plugin's EventChannel are `Map<Object?, Object?>` below the top
/// level — only the outermost map gets cast by the plugin.
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
  })  : id = _newRpcId(),
        version = wearRpcVersion;

  final String id;
  final WearRpcAction action;

  /// The *sender's* contract version, which is what tells the phone whether
  /// this watch will still be listening after a wake — see
  /// [wearRpcWakeAwareVersion].
  final int version;

  /// Required for every action except [WearRpcAction.getFleet].
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

  Map<String, dynamic> encode() => <String, dynamic>{
        _kVersion: wearRpcVersion,
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
    // Unknown action (e.g. newer watch talking to older phone) → null; the
    // phone can't execute what it doesn't know, and the watch's timeout turns
    // that silence into a fallback.
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

  /// What the *server* said, when the failure came from it — the sentence that
  /// names the missing permission on a 403. Optional by design: an older phone
  /// relays without it and the watch falls back to wording derived from
  /// [error], exactly as it did before this field existed.
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
    return WearRpcAck(id, state: _stringOrNull(map[_kState]) ?? wearRpcAckWaking);
  }
}
