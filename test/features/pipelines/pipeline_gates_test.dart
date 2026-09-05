import 'package:bambuddy_mobile/core/models/current_user.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/data/pipelines_repository.dart';
import 'package:bambuddy_mobile/features/pipelines/pipelines_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../../helpers.dart';

/// What the three entry-point gates answer, against the two things that decide
/// it: what `/auth/me` claims, and what the server actually does.
///
/// The server splits pipelines across three permissions and grants an API key
/// two of them (`core/auth.py`, since 1.2.5.3), so "may this session use
/// pipelines" has three answers and they have to be able to disagree.
void main() {
  late Dio dio;
  late DioAdapter adapter;
  late PipelinesRepository repo;

  /// A container standing in for a session: [permissions] is what `/auth/me`
  /// reported, [authMode] how it authenticated.
  ProviderContainer session({
    Set<String>? permissions,
    AuthMode authMode = AuthMode.jwt,
  }) {
    final container = ProviderContainer(overrides: [
      fakeServerProfileOverride(authMode: authMode),
      pipelinesRepositoryProvider.overrideWithValue(repo),
      if (permissions != null)
        currentUserProvider.overrideWith(
          () => _FixedUser(CurrentUser(
            id: 1,
            username: 'op',
            isAdmin: false,
            permissions: permissions,
          )),
        ),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://s.local:8000'));
    adapter = DioAdapter(dio: dio);
    repo = PipelinesRepository(dio);
  });

  void routesAnswer() => adapter.onGet(
        '/api/v1/slicer-pipelines/',
        (s) => s.reply(200, {'pipelines': []}),
      );

  test('a session that has never listed a pipeline still gets its gates',
      () async {
    // The regression this pins: the archive and file-manager Run buttons reach
    // `canRunPipelines` without ever opening the pipelines screen. A gate that
    // only read the repository latch — which the *list* route settles — would
    // answer false forever, and the button would never appear anywhere.
    routesAnswer();
    final container = session(permissions: const {
      Permissions.pipelinesRead,
      Permissions.pipelinesRun,
    });

    expect(await container.read(canRunPipelinesProvider.future), isTrue);
  });

  test('no routes on the server closes all three gates', () async {
    adapter.onGet(
      '/api/v1/slicer-pipelines/',
      (s) => s.reply(404, {'detail': 'Not Found'}),
    );
    final container = session(permissions: const {
      Permissions.pipelinesRead,
      Permissions.pipelinesRun,
      Permissions.pipelinesWrite,
    });

    expect(await container.read(pipelinesSupportedProvider.future), isFalse);
    expect(await container.read(canRunPipelinesProvider.future), isFalse);
    expect(await container.read(canWritePipelinesProvider.future), isFalse);
  });

  test('a Viewer reads pipelines and cannot run or author one', () async {
    // The default `Viewers` group is granted PIPELINES_READ alone.
    routesAnswer();
    final container = session(permissions: const {Permissions.pipelinesRead});

    expect(await container.read(pipelinesSupportedProvider.future), isTrue);
    expect(await container.read(canRunPipelinesProvider.future), isFalse);
    expect(await container.read(canWritePipelinesProvider.future), isFalse);
  });

  test('an API key is never offered authoring, whatever /auth/me claimed',
      () async {
    // `PIPELINES_WRITE` is absent from the key scope allowlist, and that gate
    // is allowlist-only — so a key is refused it on every server version.
    // Up to 1.2.5.x `/auth/me` nevertheless described a key as an admin
    // holding every permission, which is exactly the claim here.
    routesAnswer();
    final container = session(
      authMode: AuthMode.apiKey,
      permissions: const {
        Permissions.pipelinesRead,
        Permissions.pipelinesRun,
        Permissions.pipelinesWrite,
      },
    );

    expect(await container.read(canWritePipelinesProvider.future), isFalse,
        reason: 'decided on the auth mode, not on the payload');
    expect(await container.read(canRunPipelinesProvider.future), isTrue,
        reason: 'running is mapped to can_queue + can_manage_library');
    expect(await container.read(pipelinesSupportedProvider.future), isTrue);
  });

  test('an API key on a server before 1.2.5.3 sees nothing', () async {
    // There the key was denied all three permissions, so the list route 403s
    // and the probe takes the whole feature away — no version check needed.
    adapter.onGet(
      '/api/v1/slicer-pipelines/',
      (s) => s.reply(403, {'detail': 'API keys cannot be used for '
          'administrative operations'}),
    );
    final container = session(
      authMode: AuthMode.apiKey,
      permissions: const {Permissions.pipelinesRead, Permissions.pipelinesRun},
    );

    expect(await container.read(pipelinesSupportedProvider.future), isFalse);
    expect(await container.read(canRunPipelinesProvider.future), isFalse);
  });

  test('an unknown identity is trusted until the server says otherwise',
      () async {
    // Authentication off server-side: `/auth/me` has nothing to report and
    // `RequirePermissionIfAuthEnabled` answers these routes to anybody.
    routesAnswer();
    final container = session(authMode: AuthMode.none);

    expect(await container.read(pipelinesSupportedProvider.future), isTrue);
    expect(await container.read(canRunPipelinesProvider.future), isTrue);
    expect(await container.read(canWritePipelinesProvider.future), isTrue);
  });
}

class _FixedUser extends CurrentUserNotifier {
  _FixedUser(this._user);
  final CurrentUser _user;

  @override
  Future<CurrentUser?> build() async => _user;
}
