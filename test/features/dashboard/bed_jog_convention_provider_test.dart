import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/api/server_version.dart';
import 'package:bambuddy_mobile/core/printers/bed_jog.dart';
import 'package:bambuddy_mobile/data/printer_commands_repository.dart';
import 'package:bambuddy_mobile/features/dashboard/controls_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _OpenApi implements PrinterCommandsRepository {
  _OpenApi(this.answer);

  /// The decoded document, or an exception to throw.
  final Object? answer;
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

const _fixedDoc = {
  'paths': {
    '/api/v1/printers/{printer_id}/bed-jog': {
      'post': {'summary': 'Bed Jog'},
    },
  },
};

Future<(BedJogConvention, int)> resolve(String? version, Object? answer) async {
  final repo = _OpenApi(answer);
  final container = ProviderContainer(
    overrides: [
      serverVersionProvider.overrideWith(
        (ref) async => ServerVersion.tryParse(version),
      ),
      printerCommandsRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);
  final convention = await container.read(bedJogConventionProvider.future);
  return (convention, repo.fetches);
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

  test('an unknown version asks the schema too', () async {
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
}
