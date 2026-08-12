import 'package:bambuddy_mobile/core/watch/wear_rpc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WearRpcRequest', () {
    test('round-trips a command request', () {
      final req = WearRpcRequest.create(WearRpcAction.pause, printerId: 3);
      final decoded = WearRpcRequest.decode(req.encode())!;
      expect(decoded.id, req.id);
      expect(decoded.action, WearRpcAction.pause);
      expect(decoded.printerId, 3);
    });

    test('getFleet carries no printerId key (Data Layer rejects nulls)', () {
      final map = WearRpcRequest.create(WearRpcAction.getFleet).encode();
      expect(map.containsKey('printerId'), isFalse);
      expect(map['v'], wearRpcVersion);
      expect(map['kind'], 'req');
      final decoded = WearRpcRequest.decode(map)!;
      expect(decoded.action, WearRpcAction.getFleet);
      expect(decoded.printerId, isNull);
    });

    test('create() generates unique ids', () {
      final a = WearRpcRequest.create(WearRpcAction.getFleet);
      final b = WearRpcRequest.create(WearRpcAction.getFleet);
      expect(a.id, isNot(b.id));
    });

    test('response map decodes to null (shared stream carries both kinds)',
        () {
      final res = const WearRpcResponse.ok('x', {'a': 1}).encode();
      expect(WearRpcRequest.decode(res), isNull);
    });

    test('unknown action → null (newer watch vs older phone)', () {
      expect(
        WearRpcRequest.decode(
            const {'kind': 'req', 'id': 'x', 'action': 'reboot'}),
        isNull,
      );
    });

    test('foreign/malformed maps → null', () {
      expect(WearRpcRequest.decode(const {}), isNull);
      expect(WearRpcRequest.decode(const {'foo': 1}), isNull);
      expect(
        WearRpcRequest.decode(const {'kind': 'req', 'action': 'pause'}),
        isNull, // missing id
      );
    });
  });

  group('WearRpcResponse', () {
    test('round-trips ok with data', () {
      final res = const WearRpcResponse.ok('id1', {
        'printers': [
          {
            'printer': {'id': 1, 'name': 'X1C'},
            'status': {'progress': 42},
          },
        ],
      });
      final decoded = WearRpcResponse.decode(res.encode())!;
      expect(decoded.id, 'id1');
      expect(decoded.ok, isTrue);
      expect(decoded.error, isNull);
      final printers = decoded.data!['printers'] as List;
      final first = printers.first as Map<String, dynamic>;
      expect((first['printer'] as Map<String, dynamic>)['name'], 'X1C');
    });

    test('round-trips failure with error code', () {
      final decoded = WearRpcResponse.decode(
          const WearRpcResponse.failure('id2', 'empty-queue').encode())!;
      expect(decoded.ok, isFalse);
      expect(decoded.error, 'empty-queue');
      expect(decoded.data, isNull);
    });

    test('ok command response without data (pause/resume/...)', () {
      final map = const WearRpcResponse.ok('id3').encode();
      expect(map.containsKey('data'), isFalse);
      final decoded = WearRpcResponse.decode(map)!;
      expect(decoded.ok, isTrue);
      expect(decoded.data, isNull);
    });

    test(
        'decodes EventChannel-shaped maps: nested Map<Object?,Object?> '
        'become Map<String,dynamic>', () {
      // Simulate what the plugin delivers: only the top map is string-keyed.
      final wire = <Object?, Object?>{
        'v': 1,
        'kind': 'res',
        'id': 'id4',
        'ok': true,
        'data': <Object?, Object?>{
          'printers': <Object?>[
            <Object?, Object?>{
              'printer': <Object?, Object?>{'id': 7, 'name': 'P1S'},
            },
          ],
        },
      };
      final decoded = WearRpcResponse.decode(wire)!;
      final printers = decoded.data!['printers'] as List;
      // The whole subtree must be Map<String, dynamic> so model fromJson works.
      final first = printers.first as Map<String, dynamic>;
      final printer = first['printer'] as Map<String, dynamic>;
      expect(printer['id'], 7);
    });

    test('request map decodes to null', () {
      final req = WearRpcRequest.create(WearRpcAction.stop, printerId: 1);
      expect(WearRpcResponse.decode(req.encode()), isNull);
    });
  });

  /// The relay carries the server's own explanation so the watch can show the
  /// same sentence the phone would. Optional on purpose: the envelope is
  /// documented as additive, and a watch paired with an older phone must keep
  /// working on the code alone.
  group('the failure reason', () {
    test('round-trips when the phone sent one', () {
      final res = WearRpcResponse.failure(
        'abc',
        'forbidden',
        reason: "API key does not have 'can_control_printer' permission",
      );

      final back = WearRpcResponse.decode(res.encode())!;

      expect(back.ok, isFalse);
      expect(back.error, 'forbidden');
      expect(back.reason, contains('can_control_printer'));
    });

    test('an older phone omits the field and decoding still succeeds', () {
      // Exactly what a pre-field phone puts on the wire.
      final legacy = {
        'v': wearRpcVersion,
        'kind': 'res',
        'id': 'abc',
        'ok': false,
        'error': 'forbidden',
      };

      final back = WearRpcResponse.decode(legacy)!;

      expect(back.error, 'forbidden');
      expect(back.reason, isNull);
    });

    test('an empty reason reads as none rather than as an empty sentence', () {
      final back = WearRpcResponse.decode({
        'v': wearRpcVersion,
        'kind': 'res',
        'id': 'abc',
        'ok': false,
        'error': 'forbidden',
        'reason': '',
      })!;

      expect(back.reason, isNull);
    });

    test('a success carries none', () {
      final back = WearRpcResponse.decode(
        const WearRpcResponse.ok('abc', {'x': 1}).encode(),
      )!;

      expect(back.reason, isNull);
      expect(back.ok, isTrue);
    });
  });

  group('deepSanitize', () {
    test('strips nulls recursively and re-keys maps', () {
      final out = deepSanitize({
        'a': 1,
        'b': null,
        'nested': {'x': null, 'y': 'z'},
        'list': [
          {'k': null, 'v': 2},
          3,
        ],
      }) as Map<String, dynamic>;
      expect(out.containsKey('b'), isFalse);
      expect((out['nested'] as Map<String, dynamic>).containsKey('x'), isFalse);
      expect((out['nested'] as Map<String, dynamic>)['y'], 'z');
      final list = out['list'] as List;
      expect((list.first as Map<String, dynamic>)['v'], 2);
      expect(list[1], 3);
    });
  });
}
