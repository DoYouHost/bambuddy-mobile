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
}

const _kVersion = 'v';
const _kKind = 'kind';
const _kId = 'id';
const _kAction = 'action';
const _kPrinterId = 'printerId';
const _kOk = 'ok';
const _kData = 'data';
const _kError = 'error';

const _kindRequest = 'req';
const _kindResponse = 'res';

/// Contract version, bumped on incompatible changes. A decoder seeing a newer
/// version than it knows still tries to parse (fields are additive) — the
/// field exists so a future breaking change can be detected explicitly.
const wearRpcVersion = 1;

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

/// Watch→phone request.
class WearRpcRequest {
  const WearRpcRequest({
    required this.id,
    required this.action,
    this.printerId,
  });

  /// New request with a fresh correlation id.
  WearRpcRequest.create(this.action, {this.printerId}) : id = _newRpcId();

  final String id;
  final WearRpcAction action;

  /// Required for every action except [WearRpcAction.getFleet].
  final int? printerId;

  Map<String, dynamic> encode() => <String, dynamic>{
        _kVersion: wearRpcVersion,
        _kKind: _kindRequest,
        _kId: id,
        _kAction: action.name,
        if (printerId != null) _kPrinterId: printerId,
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
    return WearRpcRequest(
      id: id,
      action: action,
      printerId: printerId is int ? printerId : null,
    );
  }
}

/// Phone→watch response, correlated to the request by [id].
class WearRpcResponse {
  const WearRpcResponse.ok(this.id, [this.data])
      : ok = true,
        error = null;

  const WearRpcResponse.failure(this.id, this.error)
      : ok = false,
        data = null;

  final String id;
  final bool ok;

  /// Raw server-shaped JSON payload (shape depends on the action); null for
  /// failures and for command actions that return nothing.
  final Map<String, dynamic>? data;

  /// Short machine-readable reason (e.g. `phone-unconfigured`, `empty-queue`).
  final String? error;

  Map<String, dynamic> encode() => <String, dynamic>{
        _kVersion: wearRpcVersion,
        _kKind: _kindResponse,
        _kId: id,
        _kOk: ok,
        if (data != null) _kData: deepSanitize(data),
        if (error != null) _kError: error,
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
    return WearRpcResponse.failure(id, error is String ? error : 'unknown');
  }
}
