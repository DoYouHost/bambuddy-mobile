import 'dart:async';

import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/api/server_version_service.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:bambuddy_mobile/data/printer_commands_repository.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/data/queue_repository.dart';
import 'package:bambuddy_mobile/wear/wear_transport.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

const _down = ApiException(AppErrorCode.connectionError);

class _Printers extends PrintersRepository {
  _Printers({this.down = false}) : super(Dio());

  final bool down;

  @override
  Future<List<PrinterWithStatus>> fetchAll() async => down ? throw _down : [];
}

/// Answers when the test says so.
class _Queue extends QueueRepository {
  _Queue() : super(Dio());

  final answer = Completer<List<QueueItem>>();

  @override
  Future<List<QueueItem>> fetch({int? printerId, String? status}) =>
      answer.future;
}

RestTransport _transport(PrintersRepository printers, QueueRepository queue) =>
    RestTransport(
      printers: printers,
      commands: PrinterCommandsRepository(Dio()),
      queue: queue,
      serverVersion: ServerVersionService(Dio()),
    );

void main() {
  test('a printer list that fails does not wait for the queue', () async {
    // The queue never answers; an uncaught error would fail the test too.
    final fleet = _transport(_Printers(down: true), _Queue()).getFleet();

    await expectLater(fleet, throwsA(same(_down)));
  });

  test('a queue that fails in any way only makes the count unknown', () async {
    final queue = _Queue()..answer.completeError(TypeError());
    final fleet = await _transport(_Printers(), queue).getFleet();

    expect(fleet.printers, isEmpty);
    expect(fleet.queuePending, isNull);
  });
}
