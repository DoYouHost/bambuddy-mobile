import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/data/queue_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

/// The three routes that take an item out of the queue, and the one thing they
/// have in common: each refuses a status it does not handle, and says which
/// status it found only in the 400's `detail`.
///
/// Issue #35 is what happens when that detail is dropped — the reporter's
/// screen could say no more than "server returned error 400" about a row that
/// had no working removal at all.
void main() {
  late Dio dio;
  late DioAdapter adapter;
  late QueueRepository repo;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://s.local:8000'));
    adapter = DioAdapter(dio: dio);
    repo = QueueRepository(dio);
  });

  test('stop: posts to the route a printing item accepts', () async {
    var hit = false;
    adapter.onPost('/api/v1/queue/224/stop', (server) {
      hit = true;
      server.reply(200, {'message': 'Print stopped'});
    });

    await repo.stop(224);

    expect(hit, isTrue,
        reason: '/stop is the only route that clears a printing row');
  });

  test('stop: an offline printer still clears the row', () async {
    // The server writes the item `cancelled` whether or not the stop command
    // reached the machine, and only the message differs. Nothing to assert but
    // that the app treats it as success.
    adapter.onPost(
      '/api/v1/queue/224/stop',
      (server) => server.reply(
          200, {'message': 'Queue item cancelled (printer was offline)'}),
    );

    await expectLater(repo.stop(224), completes);
  });

  test('stop: keeps the status the server named in a 400', () async {
    adapter.onPost(
      '/api/v1/queue/9/stop',
      (server) => server.reply(400, {
        'detail': "Can only stop items that are printing, current status: "
            "'pending'",
      }),
    );

    final error = await _failureOf(() => repo.stop(9));

    expect(error.statusCode, 400);
    expect(error.detail, contains('pending'),
        reason: 'the status is the whole explanation of the refusal');
  });

  test('cancel: keeps the status the server named in a 400', () async {
    // Verbatim what the reporter's server answered, item 224 included.
    adapter.onPost(
      '/api/v1/queue/224/cancel',
      (server) => server.reply(
          400, {'detail': "Cannot cancel item with status 'printing'"}),
    );

    final error = await _failureOf(() => repo.cancel(224));

    expect(error.detail, "Cannot cancel item with status 'printing'");
  });

  test('delete: keeps the reason a printing row cannot be deleted', () async {
    adapter.onDelete(
      '/api/v1/queue/224',
      (server) => server.reply(
          400, {'detail': 'Cannot delete item that is currently printing'}),
    );

    final error = await _failureOf(() => repo.delete(224));

    expect(error.detail, 'Cannot delete item that is currently printing');
  });

  test('updateItem: keeps the reason an edit came too late', () async {
    // The edit form's own refusal — the item started printing while the user
    // was in the form — and the screen shows it through the same table.
    adapter.onPatch(
      '/api/v1/queue/224',
      (server) =>
          server.reply(400, {'detail': 'Can only update pending items'}),
      data: Matchers.any,
    );

    final error = await _failureOf(() => repo.updateItem(224, plateId: 2));

    expect(error.detail, 'Can only update pending items');
  });

  test('delete: a 403 still carries what the server refused', () async {
    // The detail-keeping mapper only adds 400/422 to what the plain one
    // already does, so ownership refusals must survive it unchanged.
    adapter.onDelete(
      '/api/v1/queue/5',
      (server) => server
          .reply(403, {'detail': 'You can only delete your own queue items'}),
    );

    final error = await _failureOf(() => repo.delete(5));

    expect(error.code, AppErrorCode.forbidden);
    expect(error.detail, 'You can only delete your own queue items');
  });
}

Future<AppApiException> _failureOf(Future<void> Function() send) async {
  try {
    await send();
  } on AppApiException catch (e) {
    return e;
  }
  fail('expected the route to be refused');
}
