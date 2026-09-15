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

class _DownPrinters extends PrintersRepository {
  _DownPrinters() : super(Dio());

  @override
  Future<List<PrinterWithStatus>> fetchAll() async => throw _down;
}

/// Answers only when the test says so, so the printer list fails first.
class _HeldQueue extends QueueRepository {
  _HeldQueue() : super(Dio());

  final answer = Completer<List<QueueItem>>();

  @override
  Future<List<QueueItem>> fetch({int? printerId, String? status}) =>
      answer.future;
}

void main() {
  test('a printer list that fails before the queue answers is not reported as '
      'uncaught', () async {
    final queue = _HeldQueue();
    final transport = RestTransport(
      printers: _DownPrinters(),
      commands: PrinterCommandsRepository(Dio()),
      queue: queue,
      serverVersion: ServerVersionService(Dio()),
    );

    final fleet = transport.getFleet();
    // Lets the printer fetch fail while the queue is still out; an uncaught
    // error here fails the test on its own.
    await Future<void>.delayed(Duration.zero);
    queue.answer.complete(const []);

    await expectLater(fleet, throwsA(same(_down)));
  });
}
