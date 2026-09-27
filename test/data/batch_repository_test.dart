import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/print_batch.dart';
import 'package:bambuddy_mobile/data/batch_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../helpers.dart';

const _path = '/api/v1/queue/batches';

Map<String, dynamic> _batch({int id = 1, bool order = true}) => {
  'id': id,
  'name': 'Order',
  'quantity': 2,
  'status': 'active',
  'created_at': '2026-09-20T10:00:00',
  if (order) ...{
    'has_targets': true,
    'target_count': 2,
    'remaining_count': 2,
    'plates': const <Object>[],
  },
};

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late BatchRepository repo;

  setUp(() {
    dio = testDio();
    adapter = DioAdapter(dio: dio);
    repo = BatchRepository(dio);
  });

  group('list', () {
    test('filters by status and learns the server has orders', () async {
      adapter.onGet(
        _path,
        queryParameters: {'status': 'active'},
        (s) => s.reply(200, [_batch(), 'junk']),
      );

      final list = await repo.list(status: PrintBatchStatus.active);

      expect(list.single.hasTargets, isTrue);
      expect(repo.ordersCapability.observedAnswer, isTrue);
      expect(repo.listCapability.observedAnswer, isTrue);
    });

    test('a row without has_targets is a server before orders', () async {
      adapter.onGet(_path, (s) => s.reply(200, [_batch(order: false)]));

      await repo.list();

      expect(repo.ordersCapability.observedAnswer, isFalse);
    });

    test('an empty list settles nothing about orders', () async {
      adapter.onGet(_path, (s) => s.reply(200, <Object>[]));

      await repo.list();

      expect(repo.ordersCapability.observedAnswer, isNull);
    });

    test('404 is a server without batches', () async {
      adapter.onGet(_path, (s) => s.reply(404, {'detail': 'Not Found'}));

      await expectLater(repo.list(), throwsA(isA<AppApiException>()));
      expect(repo.listCapability.observedAnswer, isFalse);
    });

    test('500 settles nothing', () async {
      adapter.onGet(_path, (s) => s.reply(500, {'detail': 'boom'}));

      await expectLater(repo.list(), throwsA(isA<AppApiException>()));
      expect(repo.listCapability.observedAnswer, isNull);
    });
  });

  test('a 404 on one batch is that batch, not the route', () async {
    adapter.onGet('$_path/5', (s) => s.reply(404, {'detail': 'Not found'}));

    await expectLater(repo.get(5), throwsA(isA<AppApiException>()));
    expect(repo.listCapability.observedAnswer, isNull);
  });

  group('create', () {
    test('a grouping sends the items and nothing else', () async {
      adapter.onPost(
        _path,
        data: {
          'name': 'Clips',
          'item_ids': [3, 4],
        },
        (s) => s.reply(200, _batch(order: false)),
      );

      final b = await repo.create(name: 'Clips', itemIds: [3, 4]);
      expect(b.hasTargets, isFalse);
    });

    test('an order keeps the whole-file plate and numbers the rows', () async {
      adapter.onPost(
        _path,
        data: {
          'name': 'Set',
          'library_file_id': 9,
          'plates': [
            {'plate_id': null, 'quantity_target': 3, 'sort_order': 0},
            {
              'plate_id': 2,
              'plate_name': 'Rings',
              'quantity_target': 0,
              'sort_order': 1,
            },
          ],
          // Naive UTC, the column's own form.
          'due_date': '2026-09-30T21:59:59',
          'notes': 'n',
        },
        (s) => s.reply(200, _batch()),
      );

      await repo.create(
        name: 'Set',
        libraryFileId: 9,
        plates: const [
          (plateId: null, plateName: null, quantity: 3),
          (plateId: 2, plateName: 'Rings', quantity: 0),
        ],
        dueDate: DateTime.utc(2026, 9, 30, 21, 59, 59),
        notes: 'n',
      );
    });

    test('a refusal keeps the sentence', () async {
      adapter.onPost(
        _path,
        data: {'name': ' '},
        (s) => s.reply(400, {'detail': 'Batch name is required'}),
      );

      await expectLater(
        repo.create(name: ' '),
        throwsA(
          isA<ApiException>().having(
            (e) => e.detail,
            'detail',
            'Batch name is required',
          ),
        ),
      );
    });
  });

  test('update sends only what changed', () async {
    adapter.onPatch(
      '$_path/1',
      data: {'notes': '', 'status': 'active'},
      (s) => s.reply(200, _batch()),
    );

    await repo.update(1, notes: '', status: PrintBatchStatus.active);
  });

  group('dispatch', () {
    test('everything owed: an empty body', () async {
      adapter.onPost(
        '$_path/1/dispatch',
        data: <String, dynamic>{},
        (s) => s.reply(200, _batch()),
      );

      await repo.dispatch(1);
    });

    test('the whole-file plate is named as null, with only_plate', () async {
      adapter.onPost(
        '$_path/1/dispatch',
        data: {'plate_id': null, 'only_plate': true},
        (s) => s.reply(200, _batch()),
      );

      await repo.dispatch(1, plate: const PrintBatchPlate());
    });

    test('a stranded refusal keeps the plate names', () async {
      adapter.onPost(
        '$_path/1/dispatch',
        data: <String, dynamic>{},
        (s) => s.reply(400, {
          'detail':
              'Rings has no queued or finished run to copy settings from.',
        }),
      );

      await expectLater(
        repo.dispatch(1),
        throwsA(
          isA<ApiException>().having(
            (e) => e.detail,
            'detail',
            contains('Rings'),
          ),
        ),
      );
    });
  });

  test('ungroup answers how many items left', () async {
    adapter.onPost(
      '$_path/1/ungroup',
      (s) => s.reply(200, {'ungrouped_count': 3, 'message': 'Ungrouped 3'}),
    );

    expect(await repo.ungroup(1), 3);
  });

  test('cancel is a DELETE', () async {
    adapter.onDelete(
      '$_path/1',
      (s) => s.reply(200, {'message': 'Batch cancelled'}),
    );

    await repo.cancel(1);
  });
}
