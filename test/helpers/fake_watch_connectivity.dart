import 'dart:async';

import 'package:watch_connectivity/watch_connectivity.dart';

/// Fake Data Layer: records sent messages, lets tests deliver incoming ones
/// and script automatic replies. `noSuchMethod` absorbs the plugin members the
/// code under test never touches.
/// The plugin base is @immutable; this test double is deliberately mutable.
// ignore: must_be_immutable
class FakeWatchConnectivity implements WatchConnectivity {
  final _incoming = StreamController<Map<String, dynamic>>.broadcast();
  final sent = <Map<String, dynamic>>[];
  bool reachable = true;

  /// A Data Layer channel that has hung: the call never answers at all, which
  /// is the one wait in a relay request with no deadline of its own.
  bool hangReachable = false;
  bool hangSend = false;

  /// When set, `isReachable` answers with this instead — for a test that has to
  /// put something between the question and the answer.
  Completer<bool>? reachableGate;

  /// When set, every sent message is answered with this function's result.
  Map<String, dynamic>? Function(Map<String, dynamic> request)? autoRespond;

  @override
  Stream<Map<String, dynamic>> get messageStream => _incoming.stream;

  @override
  Future<bool> get isReachable {
    if (hangReachable) return Completer<bool>().future;
    return reachableGate?.future ?? Future.value(reachable);
  }

  @override
  Future<void> sendMessage(Map<String, dynamic> message) {
    sent.add(message);
    if (hangSend) return Completer<void>().future;
    final reply = autoRespond?.call(message);
    if (reply != null) _incoming.add(reply);
    return Future.value();
  }

  void deliver(Map<String, dynamic> message) => _incoming.add(message);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
