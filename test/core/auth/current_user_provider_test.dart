import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/demo/demo_config.dart';
import 'package:bambuddy_mobile/core/models/current_user.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/data/account_repository.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Profile the test drives by hand — `currentUserProvider` watches it, so
/// setting one is what stands in for "a session was restored at startup".
class _TestProfileNotifier extends ServerProfileNotifier {
  static ServerProfile? initial;

  @override
  ServerProfile? build() => initial;

  void set(ServerProfile? profile) => state = profile;
}

class _FakeAccount implements AccountRepository {
  _FakeAccount({this.user});

  CurrentUser? user;
  Object? error;
  int calls = 0;

  @override
  Future<CurrentUser> me() async {
    calls++;
    if (error != null) throw error!;
    return user!;
  }
}

CurrentUser _user({
  bool isAdmin = false,
  Set<String> permissions = const {},
  bool permissionsKnown = true,
}) =>
    CurrentUser(
      id: 1,
      username: 'u',
      isAdmin: isAdmin,
      permissions: permissions,
      permissionsKnown: permissionsKnown,
    );

const _jwtProfile =
    ServerProfile(baseUrl: 'http://s.local:8000', authMode: AuthMode.jwt);

void main() {
  late _FakeAccount account;

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        serverProfileProvider.overrideWith(_TestProfileNotifier.new),
        accountRepositoryProvider.overrideWithValue(account),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUp(() {
    _TestProfileNotifier.initial = null;
    account = _FakeAccount(user: _user());
  });

  group('currentUserProvider', () {
    test('without a profile nobody is signed in and nothing is asked',
        () async {
      final container = makeContainer();

      expect(await container.read(currentUserProvider.future), isNull);
      expect(account.calls, 0);
    });

    test('a restored session reads GET /auth/me once', () async {
      // Startup path: the profile comes from settings, no login ran, so the
      // identity has to be re-established from the server.
      _TestProfileNotifier.initial = _jwtProfile;
      account.user = _user(permissions: {'users:read'});
      final container = makeContainer();

      final user = await container.read(currentUserProvider.future);
      expect(user?.can(Permissions.usersRead), isTrue);
      expect(account.calls, 1);

      // A second read is served from the same state, not from the server.
      await container.read(currentUserProvider.future);
      expect(account.calls, 1);
    });

    test('a user handed over by login costs no request', () async {
      final container = makeContainer();
      await container.read(currentUserProvider.future);

      container.read(currentUserProvider.notifier).adopt(_user(isAdmin: true));
      // Saving the profile is what a finished login does next, and it rebuilds
      // the notifier — the hand-off has to survive that.
      (container.read(serverProfileProvider.notifier) as _TestProfileNotifier)
          .set(_jwtProfile);

      final user = await container.read(currentUserProvider.future);
      expect(user?.isAdmin, isTrue);
      expect(account.calls, 0);
    });

    test('the hand-off is spent once — the next profile change refetches',
        () async {
      final container = makeContainer();
      await container.read(currentUserProvider.future);
      final notifier =
          container.read(serverProfileProvider.notifier) as _TestProfileNotifier;

      container.read(currentUserProvider.notifier).adopt(_user(isAdmin: true));
      notifier.set(_jwtProfile);
      await container.read(currentUserProvider.future);
      expect(account.calls, 0);

      // Switching servers must not carry the previous server's identity over.
      account.user = _user(permissions: {'groups:read'});
      notifier.set(const ServerProfile(
        baseUrl: 'http://other.local:8000',
        authMode: AuthMode.jwt,
      ));
      final user = await container.read(currentUserProvider.future);
      expect(account.calls, 1);
      expect(user?.can(Permissions.groupsRead), isTrue);
    });

    test('a server with auth off is not asked at all', () async {
      // `/auth/me` requires credentials and would only answer 401 there.
      _TestProfileNotifier.initial = const ServerProfile(
        baseUrl: 'http://s.local:8000',
        authMode: AuthMode.none,
      );
      final container = makeContainer();

      expect(await container.read(currentUserProvider.future), isNull);
      expect(account.calls, 0);
    });

    test('the demo profile is asked, despite carrying no credentials',
        () async {
      // The demo backend serves `/auth/me` itself, so the app shows the demo
      // identity rather than an unknown one.
      _TestProfileNotifier.initial = const ServerProfile(
        baseUrl: DemoConfig.baseUrl,
        authMode: AuthMode.none,
      );
      account.user = _user(isAdmin: true);
      final container = makeContainer();

      expect((await container.read(currentUserProvider.future))?.isAdmin, isTrue);
      expect(account.calls, 1);
    });

    test('a failed request leaves the identity unknown, not an error state',
        () async {
      // An older server (404) or an offline one must not put an error on the
      // screen — nothing here is user-facing on its own.
      _TestProfileNotifier.initial = _jwtProfile;
      account.error = const ApiException(AppErrorCode.serverUnreachable);
      final container = makeContainer();

      expect(await container.read(currentUserProvider.future), isNull);
      expect(container.read(currentUserProvider).hasError, isFalse);
    });

    test('refresh re-reads the server', () async {
      _TestProfileNotifier.initial = _jwtProfile;
      account.user = _user(permissions: {'users:read'});
      final container = makeContainer();
      await container.read(currentUserProvider.future);

      // Permissions can change while the app is open.
      account.user = _user(permissions: {'users:read', 'groups:read'});
      await container.read(currentUserProvider.notifier).refresh();

      expect(account.calls, 2);
      expect(container.read(permissionProvider(Permissions.groupsRead)), isTrue);
    });

    test('signing out drops the identity', () async {
      _TestProfileNotifier.initial = _jwtProfile;
      final container = makeContainer();
      await container.read(currentUserProvider.future);

      (container.read(serverProfileProvider.notifier) as _TestProfileNotifier)
          .set(null);

      expect(await container.read(currentUserProvider.future), isNull);
    });
  });

  group('permissionProvider / isAdminProvider', () {
    test('follow what the user was granted', () async {
      _TestProfileNotifier.initial = _jwtProfile;
      account.user = _user(permissions: {'users:read'});
      final container = makeContainer();
      await container.read(currentUserProvider.future);

      expect(container.read(permissionProvider(Permissions.usersRead)), isTrue);
      expect(container.read(permissionProvider(Permissions.groupsRead)), isFalse);
      expect(container.read(isAdminProvider), isFalse);
    });

    test('a user granted nothing is refused, not treated as unknown', () async {
      _TestProfileNotifier.initial = _jwtProfile;
      account.user = _user();
      final container = makeContainer();
      await container.read(currentUserProvider.future);

      expect(container.read(permissionProvider(Permissions.usersRead)), isFalse);
      expect(container.read(isAdminProvider), isFalse);
    });

    test('an admin passes everything', () async {
      _TestProfileNotifier.initial = _jwtProfile;
      account.user = _user(isAdmin: true);
      final container = makeContainer();
      await container.read(currentUserProvider.future);

      expect(container.read(permissionProvider(Permissions.apiKeysRead)), isTrue);
      expect(container.read(isAdminProvider), isTrue);
    });

    test('an unknown identity stays permissive — the server enforces', () async {
      // Still loading, no profile, a server that never answered: none of these
      // are a "no", and answering no would hide screens the user may have.
      final container = makeContainer();

      expect(container.read(permissionProvider(Permissions.usersRead)), isTrue);
      expect(container.read(isAdminProvider), isTrue);

      _TestProfileNotifier.initial = _jwtProfile;
      account.error = const ApiException(AppErrorCode.serverUnreachable);
      final failed = makeContainer();
      await failed.read(currentUserProvider.future);

      expect(failed.read(permissionProvider(Permissions.usersRead)), isTrue);
      expect(failed.read(isAdminProvider), isTrue);
    });

    test('a server that sends no permissions field grants everything',
        () async {
      _TestProfileNotifier.initial = _jwtProfile;
      account.user = _user(permissionsKnown: false);
      final container = makeContainer();
      await container.read(currentUserProvider.future);

      expect(container.read(permissionProvider(Permissions.usersRead)), isTrue);
      expect(container.read(permissionProvider('anything:at:all')), isTrue);
    });
  });
}
