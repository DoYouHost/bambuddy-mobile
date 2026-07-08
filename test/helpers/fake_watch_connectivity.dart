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

  /// When set, every sent message is answered with this function's result.
  Map<String, dynamic>? Function(Map<String, dynamic> request)? autoRespond;

  @override
  Stream<Map<String, dynamic>> get messageStream => _incoming.stream;

  @override
  Future<bool> get isReachable async => reachable;

  @override
  Future<void> sendMessage(Map<String, dynamic> message) async {
    sent.add(message);
    final reply = autoRespond?.call(message);
    if (reply != null) _incoming.add(reply);
  }

  void deliver(Map<String, dynamic> message) => _incoming.add(message);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
