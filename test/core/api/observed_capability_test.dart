import 'package:bambuddy_mobile/core/api/observed_capability.dart';
import 'package:bambuddy_mobile/core/api/server_version.dart';
import 'package:bambuddy_mobile/core/api/server_version_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://s.local:8000'));
    adapter = DioAdapter(dio: dio);
  });

  ObservedCapability capability(String? version, {bool whenUnknown = false}) {
    if (version != null) {
      adapter.onGet(
        '/api/v1/updates/version',
        (s) => s.reply(200, {'version': version, 'repo': 'x/y'}),
      );
    }
    return ObservedCapability(
      // A 1.2.6 row, so `1.2.5.1` is the older contract and `1.2.6b1` the newer.
      ServerFeature.crossModelVariants,
      version == null ? null : ServerVersionService(dio),
      whenUnknown: whenUnknown,
    );
  }

  test('with nothing seen it answers from the version table', () async {
    expect(await capability('1.2.5.1').supported, isFalse);
    // A beta of the cycle that introduced the feature counts as having it.
    expect(await capability('1.2.6b1').supported, isTrue);
  });

  test('no version service at all falls back to whenUnknown', () async {
    expect(await capability(null).supported, isFalse);
    expect(await capability(null, whenUnknown: true).supported, isTrue);
  });

  test('what was observed outranks the version, in both directions', () async {
    final older = capability('1.2.5.1')..observe(present: true);
    expect(await older.supported, isTrue);

    final newer = capability('1.2.6b1')..observe(present: false);
    expect(await newer.supported, isFalse);
  });

  test('a refusal outranks both, and a later reply clears it', () async {
    final cap = capability('1.2.6b1')..observeRefusal();
    expect(await cap.supported, isFalse,
        reason: 'the route is there, this session may not use it');

    cap.observe(present: true);
    expect(await cap.supported, isTrue,
        reason: 'a reply that arrived says the refusal is over');
  });

  test('a route\'s own answer: 404 absent, 403 refused, the rest silent',
      () async {
    expect(await (capability('1.2.6b1')..observeFailure(404)).supported, isFalse);
    expect(await (capability('1.2.6b1')..observeFailure(403)).supported, isFalse);
    // 401, 5xx and no response at all say nothing about the route — pinning
    // either latch on them would disable a feature over a flaky network.
    for (final status in [null, 401, 500, 502]) {
      expect(await (capability('1.2.6b1')..observeFailure(status)).supported,
          isTrue,
          reason: 'status $status must leave the version reading standing');
    }
  });

  test('unversioned: offered until the route says otherwise', () async {
    expect(await ObservedCapability.unversioned().supported, isTrue);
    expect(
      await (ObservedCapability.unversioned()..observeFailure(404)).supported,
      isFalse,
    );
  });
}
