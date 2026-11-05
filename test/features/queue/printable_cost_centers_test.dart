import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/cost_center.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/data/finance_repository.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// What the print form is given to choose from, read through the provider it
/// watches rather than the repository alone: the filtering, the billing switch
/// and the refusal-is-not-empty rule all live between the two.
void main() {
  const path = '/api/v1/finance/cost-centers/mine';

  ({ProviderContainer container, RequestLog log}) rig({
    required bool billing,
    int status = 200,
    Object? body = const <Object>[],
    AuthMode? authMode,
  }) {
    final dio = testDio();
    final log = captureRequests(dio);
    mockServer(dio).onGet(path, (s) => s.reply(status, body));
    final container = ProviderContainer(
      retry: neverRetry,
      overrides: [
        authMode == null
            ? noServerProfileOverride
            : fakeServerProfileOverride(authMode: authMode),
        financeRepositoryProvider.overrideWithValue(FinanceRepository(dio)),
        serverUiFlagsProvider.overrideWith(
          (ref) async => {'billing_enabled': billing},
        ),
        serverSettingsOverride(const {}),
      ],
    );
    addTearDown(container.dispose);
    return (container: container, log: log);
  }

  /// The provider's answer once the flags have settled.
  Future<List<CostCenter>?> read(ProviderContainer container) async {
    final sub = container.listen(printableCostCentersProvider, (_, _) {});
    addTearDown(sub.close);
    await container.read(serverUiFlagsProvider.future);
    return container.read(printableCostCentersProvider.future);
  }

  test(
    'lists only what a print can be booked to, in the server order',
    () async {
      final r = rig(
        billing: true,
        body: [
          {'id': 1, 'name': 'Alice', 'is_private': true},
          {'id': 2, 'name': 'Classroom', 'can_print': false},
          {'id': 3, 'name': 'Old', 'is_active': false},
          {'id': 4, 'name': 'Workshop'},
        ],
      );

      final centers = await read(r.container);

      expect(centers?.map((c) => c.name), ['Alice', 'Workshop']);
    },
  );

  test('asks nothing, and offers nothing, without billing', () async {
    final r = rig(billing: false);

    expect(await read(r.container), isEmpty);
    expect(r.log.calls, isEmpty);
  });

  for (final status in [401, 403]) {
    test(
      'a $status is null — not "none", which an administrator fixes',
      () async {
        final r = rig(billing: true, status: status, body: {'detail': 'no'});

        expect(await read(r.container), isNull);
        expect(r.log.calls, ['GET $path']);
      },
    );
  }

  test('a lost password session is an error, not a refusal', () async {
    final r = rig(
      billing: true,
      status: 401,
      body: {'detail': 'Authentication required'},
      authMode: AuthMode.jwt,
    );

    await expectLater(read(r.container), throwsA(isA<AuthException>()));
  });

  for (final mode in [AuthMode.apiKey, AuthMode.none]) {
    test('a 401 on ${mode.name} is a refusal', () async {
      final r = rig(
        billing: true,
        status: 401,
        body: {'detail': 'x'},
        authMode: mode,
      );

      expect(await read(r.container), isNull);
    });
  }

  test('a server error is an error, which the form offers to retry', () async {
    final r = rig(billing: true, status: 500, body: {'detail': 'boom'});

    await expectLater(read(r.container), throwsA(isA<ApiException>()));
  });

  test('an empty list stays empty', () async {
    final r = rig(billing: true);

    expect(await read(r.container), isEmpty);
  });
}
