import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
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

  group('watching', () {
    /// A request that fails the way Dio fails, so the wrapper sees what a
    /// repository sees.
    Future<T> refusing<T>(int status) => Future<T>.error(DioException(
          requestOptions: RequestOptions(path: '/x'),
          // badResponse, or `mapDioException` reads it as a transport failure
          // and no status reaches the mapping at all.
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(path: '/x'),
            statusCode: status,
          ),
        ));

    test('an answer is the answer, and records the route as there', () async {
      final cap = capability('1.2.5.1');

      expect(await cap.watching(() async => 'ok'), 'ok');
      // The version said no; the reply outranks it.
      expect(await cap.supported, isTrue);
    });

    test('the two statuses the latch reads come back as the caller\'s answer',
        () async {
      for (final status in [404, 403]) {
        final cap = capability('1.2.6b1');

        expect(
          await cap.watching(() => refusing<List<int>>(status),
              absent: () => const []),
          isEmpty,
        );
        expect(await cap.supported, isFalse,
            reason: 'status $status is also recorded, not only answered');
      }
    });

    test('absentOn narrows it, so a refusal still reaches the user', () async {
      final cap = capability('1.2.6b1');

      expect(
        await cap.watching(() => refusing<String?>(404),
            absent: () => null, absentOn: const {404}),
        isNull,
      );
      await expectLater(
        cap.watching(() => refusing<String?>(403),
            absent: () => null, absentOn: const {404}),
        throwsA(isA<AuthException>()),
      );
      // And the refusal is still on the latch, whether or not it was thrown.
      expect(await cap.supported, isFalse);
    });

    test('with no answer to give, every failure throws mapped', () async {
      final cap = capability('1.2.6b1');

      await expectLater(
        cap.watching(() => refusing<String>(404)),
        throwsA(isA<AppApiException>()),
      );
      expect(await cap.supported, isFalse);
    });

    test('a failure that says nothing about the route throws and pins nothing',
        () async {
      final cap = capability('1.2.6b1');

      await expectLater(
        cap.watching(() => refusing<List<int>>(500), absent: () => const []),
        throwsA(isA<AppApiException>()),
        reason: 'a 500 is a fault to report, not an empty shelf',
      );
      expect(await cap.supported, isTrue);
    });

    test('anything that is not a Dio failure passes straight through',
        () async {
      final cap = capability('1.2.6b1');

      await expectLater(
        cap.watching<int>(() => throw StateError('parser')),
        throwsA(isA<StateError>()),
      );
    });
  });
}
