import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/api/server_version.dart';
import 'package:bambuddy_mobile/core/api/server_version_service.dart';
import 'package:bambuddy_mobile/core/printers/bed_jog.dart';
import 'package:bambuddy_mobile/data/printer_commands_repository.dart';
import 'package:bambuddy_mobile/features/dashboard/controls_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _OpenApi implements PrinterCommandsRepository {
  _OpenApi(this.answer);

  /// The decoded document, or an exception to throw.
  Object? answer;
  int fetches = 0;

  @override
  Future<Object?> fetchOpenApi() async {
    fetches++;
    if (answer is Exception) throw answer!;
    return answer;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// A server whose version can change under a running app; `null` is a read
/// that failed.
class _Version extends ServerVersionService {
  _Version(this.answer) : super(Dio());

  String? answer;

  @override
  Future<ServerVersion?> refresh() async => ServerVersion.tryParse(answer);

  @override
  Future<ServerVersion?> current() =>
      throw StateError('a cached read could be from before an upgrade');
}

const _fixedDoc = {
  'paths': {
    '/api/v1/printers/{printer_id}/bed-jog': {
      'post': {'summary': 'Bed Jog'},
    },
  },
};

({ProviderContainer container, _Version version, _OpenApi openApi}) setUpServer(
  String? version,
  Object? openApi,
) {
  final v = _Version(version);
  final o = _OpenApi(openApi);
  final container = ProviderContainer(
    overrides: [
      serverVersionServiceProvider.overrideWithValue(v),
      printerCommandsRepositoryProvider.overrideWithValue(o),
    ],
  );
  addTearDown(container.dispose);
  return (container: container, version: v, openApi: o);
}

Future<(BedJogConvention, int)> resolve(String? version, Object? answer) async {
  final s = setUpServer(version, answer);
  final convention = await s.container.read(bedJogConventionProvider.future);
  return (convention, s.openApi.fetches);
}

void main() {
  test('a release number decides without fetching the schema', () async {
    expect(await resolve('1.2.5.5', _fixedDoc), (
      BedJogConvention.flippedOnA1,
      0,
    ));
    expect(await resolve('1.2.5.6', null), (BedJogConvention.direct, 0));
  });

  test('1.2.6b1 asks the schema', () async {
    expect(await resolve('1.2.6b1', _fixedDoc), (BedJogConvention.direct, 1));
  });

  test('a failed version read asks the schema too', () async {
    expect(await resolve(null, _fixedDoc), (BedJogConvention.direct, 1));
  });

  test('a schema that cannot be read leaves the sign unknown', () async {
    expect(
      await resolve(
        '1.2.6b1',
        const NetworkException(AppErrorCode.serverUnreachable),
      ),
      (BedJogConvention.unknown, 1),
    );
    expect(await resolve('1.2.6b1', '<html></html>'), (
      BedJogConvention.unknown,
      1,
    ));
  });

  test(
    'a server upgraded in place is re-read after regained contact',
    () async {
      final s = setUpServer('1.2.5.5', null);
      expect(
        await s.container.read(bedJogConventionProvider.future),
        BedJogConvention.flippedOnA1,
      );

      s.version.answer = '1.2.5.6';
      s.container.read(serverContactEpochProvider.notifier).bump();

      expect(
        await s.container.read(bedJogConventionProvider.future),
        BedJogConvention.direct,
      );
    },
  );

  test('a failed re-read is unknown, never the answer from before', () async {
    final s = setUpServer('1.2.5.5', null);
    await s.container.read(bedJogConventionProvider.future);

    s.version.answer = null;
    s.openApi.answer = const NetworkException(AppErrorCode.serverUnreachable);
    s.container.read(serverContactEpochProvider.notifier).bump();

    expect(
      await s.container.read(bedJogConventionProvider.future),
      BedJogConvention.unknown,
    );
  });
}
