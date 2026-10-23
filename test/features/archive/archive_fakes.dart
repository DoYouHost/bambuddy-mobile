import 'dart:async';

import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/archive.dart';
import 'package:bambuddy_mobile/data/archive_repository.dart';

/// An archive repository a test drives instead of a server. Anything a test
/// did not ask for throws, naming the call.
class FakeArchives implements ArchiveRepository {
  FakeArchives({this.archive, this.rows = const []});

  /// What [byId] answers, and what a verdict comes back as.
  Archive? archive;

  /// The whole archive [list] pages through, newest first.
  List<Archive> rows;

  /// Every page asked for, in order.
  final List<({int? printerId, int limit, int offset})> listed = [];

  /// What the next [list] call fails with; cleared once thrown.
  AppApiException? listError;

  /// Whether the server stored a verdict, and what it refuses it with.
  bool applied = true;
  AppApiException? error;

  /// Set before a verdict to leave it in flight until completed.
  Completer<void>? held;
  final List<({PrintVerdict? verdict, String? reason, bool clearReason})> sent =
      [];

  @override
  Future<List<Archive>> list({
    int limit = 50,
    int offset = 0,
    int? printerId,
  }) async {
    listed.add((printerId: printerId, limit: limit, offset: offset));
    final failure = listError;
    if (failure != null) {
      listError = null;
      throw failure;
    }
    return rows.skip(offset).take(limit).toList();
  }

  @override
  Future<Archive> byId(int archiveId) async => archive!;

  @override
  Future<({Archive archive, bool applied})> setVerdict(
    int archiveId,
    PrintVerdict? verdict, {
    String? reason,
    bool clearReason = false,
  }) async {
    if (error != null) throw error!;
    sent.add((verdict: verdict, reason: reason, clearReason: clearReason));
    if (held != null) await held!.future;
    return (archive: archive!, applied: applied);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not this test\'s');
}
