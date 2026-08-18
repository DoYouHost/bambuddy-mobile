import 'dart:typed_data';

import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/data/skip_objects_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records the outgoing [RequestOptions] instead of hitting the network —
/// needed here because http_mock_adapter's matcher only looks at method/path/
/// data, not headers, and the whole point of this fix is the header.
class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.reply);

  final ResponseBody Function(RequestOptions) reply;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return reply(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _empty(int status) => ResponseBody.fromString('', status);

void main() {
  late _RecordingAdapter adapter;
  late SkipObjectsRepository repo;

  void setUpWithReply(ResponseBody Function(RequestOptions) reply) {
    adapter = _RecordingAdapter(reply);
    final dio = Dio(BaseOptions(baseUrl: 'http://s.local:8000'))
      ..httpClientAdapter = adapter;
    repo = SkipObjectsRepository(dio);
  }

  test('skip: żąda Content-Type application/json i wysyła gołą listę id', () async {
    setUpWithReply((_) => _empty(200));

    await repo.skip(1, [683]);

    final req = adapter.requests.single;
    expect(req.path, '/api/v1/printers/1/print/skip-objects');
    expect(req.contentType, Headers.jsonContentType);
    expect(req.data, [683]);
  });

  test('skip: 403 wypływa jako AuthException(forbidden)', () async {
    setUpWithReply((_) => _empty(403));

    await expectLater(
      repo.skip(1, [683]),
      throwsA(isA<AuthException>()
          .having((e) => e.code, 'code', AppErrorCode.forbidden)),
    );
  });
}
