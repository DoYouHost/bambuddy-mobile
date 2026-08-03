import 'package:bambuddy_mobile/core/models/current_user.dart';
import 'package:bambuddy_mobile/core/models/group_summary.dart';
import 'package:bambuddy_mobile/core/models/user_items_count.dart';
import 'package:bambuddy_mobile/core/models/user_write.dart';
import 'package:bambuddy_mobile/data/users_repository.dart';
import 'package:bambuddy_mobile/features/admin/user_delete_dialog.dart';
import 'package:bambuddy_mobile/features/admin/user_form_screen.dart';
import 'package:bambuddy_mobile/features/admin/users_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

const _member = CurrentUser(
  id: 2,
  username: 'zosia',
  email: 'zosia@home.lan',
  isAdmin: false,
  groups: [UserGroup(id: 5, name: 'Domownicy')],
);

const _ldapMember = CurrentUser(
  id: 3,
  username: 'katalog',
  isAdmin: false,
  authSource: 'ldap',
);

/// Records what the form asked the server to do — the point of most of these
/// tests is the body, not the response.
class _FakeUsers implements UsersRepository {
  UserCreateInput? created;
  (int, UserUpdateInput)? updated;
  (int, bool)? deleted;

  @override
  Future<List<CurrentUser>> list() async => const [_member];

  @override
  Future<UserItemsCount> itemsCount(int userId) async =>
      const UserItemsCount(archives: 2, queueItems: 0, libraryFiles: 1);

  @override
  Future<CurrentUser> create(UserCreateInput body) async {
    created = body;
    return _member;
  }

  @override
  Future<CurrentUser> update(int userId, UserUpdateInput body) async {
    updated = (userId, body);
    return _member;
  }

  @override
  Future<void> delete(int userId, {required bool deleteItems}) async {
    deleted = (userId, deleteItems);
  }

  @override
  Future<AdvancedAuthStatus> advancedAuthStatus() async =>
      AdvancedAuthStatus.legacy;
}

Widget _app(
  Widget child, {
  required _FakeUsers repo,
  AdvancedAuthStatus advanced = AdvancedAuthStatus.legacy,
  List<GroupSummary> groups = const [
    GroupSummary(id: 5, name: 'Domownicy'),
    GroupSummary(id: 1, name: 'Administrators', isSystem: true),
  ],
}) =>
    ProviderScope(
      overrides: [
        usersRepositoryProvider.overrideWithValue(repo),
        advancedAuthStatusProvider.overrideWith((ref) async => advanced),
        groupOptionsProvider.overrideWith((ref) async => groups),
        currentUserProvider.overrideWith(_NobodySignedIn.new),
      ],
      child: plApp(child),
    );

class _NobodySignedIn extends CurrentUserNotifier {
  @override
  Future<CurrentUser?> build() async => null;
}

void main() {
  late _FakeUsers repo;

  setUp(() => repo = _FakeUsers());

  group('creating an account', () {
    testWidgets('will not send a password the server would reject',
        (tester) async {
      await tester.pumpWidget(_app(const UserFormScreen(), repo: repo));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Nazwa użytkownika'), 'zosia');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Hasło'), 'krotkie');
      await tester.tap(find.text('Zapisz'));
      await tester.pumpAndSettle();

      expect(find.text('Co najmniej 8 znaków.'), findsOneWidget);
      expect(repo.created, isNull);
    });

    testWidgets('sends username, password and groups', (tester) async {
      await tester.pumpWidget(_app(const UserFormScreen(), repo: repo));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Nazwa użytkownika'), 'zosia');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Hasło'), 'Sekret!23');
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Powtórz hasło'), 'Sekret!23');
      await tester.tap(find.text('Domownicy'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zapisz'));
      await tester.pumpAndSettle();

      final body = repo.created;
      expect(body, isNotNull);
      expect(body!.username, 'zosia');
      expect(body.password, 'Sekret!23');
      expect(body.groupIds, [5]);
      // No role is ever chosen here: admin comes from the Administrators
      // group, exactly as bambuddy's own form does it.
      expect(body.role, UserRoles.user);
    });

    testWidgets('will not create an account from two different passwords',
        (tester) async {
      await tester.pumpWidget(_app(const UserFormScreen(), repo: repo));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Nazwa użytkownika'), 'zosia');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Hasło'), 'Sekret!23');
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Powtórz hasło'), 'Sekret!24');
      await tester.tap(find.text('Zapisz'));
      await tester.pumpAndSettle();

      expect(find.text('Hasła się różnią.'), findsOneWidget);
      expect(repo.created, isNull);
    });

    testWidgets('marks the groups that ship with the server', (tester) async {
      await tester.pumpWidget(_app(const UserFormScreen(), repo: repo));
      await tester.pumpAndSettle();

      expect(find.text('(wbudowana)'), findsOneWidget);
      expect(find.text('Administrators'), findsOneWidget);
      expect(find.textContaining('Administratorem czyni konto'), findsOneWidget);
    });

    testWidgets('asks for no password when the server mails one',
        (tester) async {
      await tester.pumpWidget(_app(
        const UserFormScreen(),
        repo: repo,
        advanced:
            const AdvancedAuthStatus(enabled: true, smtpConfigured: true),
      ));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextFormField, 'Hasło'), findsNothing);
      expect(find.textContaining('Serwer sam ustala hasło'), findsOneWidget);

      // The e-mail is what the password is mailed to, so it stops being
      // optional — saving without one gets nowhere.
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Nazwa użytkownika'), 'zosia');
      await tester.tap(find.text('Zapisz'));
      await tester.pumpAndSettle();

      expect(find.text('Uzupełnij to pole'), findsOneWidget);
      expect(repo.created, isNull);
    });

    testWidgets('warns when the mail carrying that password cannot be sent',
        (tester) async {
      await tester.pumpWidget(_app(
        const UserFormScreen(),
        repo: repo,
        advanced:
            const AdvancedAuthStatus(enabled: true, smtpConfigured: false),
      ));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Serwer poczty nie jest skonfigurowany'),
        findsOneWidget,
      );
    });
  });

  group('editing an account', () {
    testWidgets('sends only what changed', (tester) async {
      await tester.pumpWidget(
        _app(const UserFormScreen(existing: _member), repo: repo),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(SwitchListTile, 'Aktywne'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zapisz'));
      await tester.pumpAndSettle();

      // PATCH acts on "field present", so an untouched username must not be
      // sent — it would re-run the uniqueness check against itself.
      expect(repo.updated?.$1, 2);
      final body = repo.updated!.$2;
      expect(body.isActive, isFalse);
      expect(body.username, isNull);
      expect(body.email, isNull);
      expect(body.role, isNull);
      expect(body.groupIds, isNull);
    });

    testWidgets('leaves the password alone when the field is left empty',
        (tester) async {
      await tester.pumpWidget(
        _app(const UserFormScreen(existing: _member), repo: repo),
      );
      await tester.pumpAndSettle();

      // Nothing to confirm until a new password is typed, so the second field
      // stays out of the way.
      expect(
        find.widgetWithText(TextFormField, 'Powtórz hasło'),
        findsNothing,
      );

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Nazwa użytkownika'), 'zosia2');
      await tester.tap(find.text('Zapisz'));
      await tester.pumpAndSettle();

      expect(repo.updated!.$2.username, 'zosia2');
      expect(repo.updated!.$2.password, isNull);
    });

    testWidgets('asks to repeat a new password once one is typed',
        (tester) async {
      await tester.pumpWidget(
        _app(const UserFormScreen(existing: _member), repo: repo),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Nowe hasło'), 'Sekret!23');
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextFormField, 'Powtórz hasło'), findsOneWidget);

      await tester.tap(find.text('Zapisz'));
      await tester.pumpAndSettle();

      expect(find.text('Hasła się różnią.'), findsOneWidget);
      expect(repo.updated, isNull);
    });

    testWidgets('never sends a role — group membership carries admin',
        (tester) async {
      await tester.pumpWidget(
        _app(const UserFormScreen(existing: _member), repo: repo),
      );
      await tester.pumpAndSettle();

      expect(find.text('Rola'), findsNothing);

      await tester.tap(find.text('Administrators'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zapisz'));
      await tester.pumpAndSettle();

      expect(repo.updated!.$2.role, isNull);
      expect(repo.updated!.$2.groupIds, [1, 5]);
    });

    testWidgets('offers no password field for a directory account',
        (tester) async {
      await tester.pumpWidget(
        _app(const UserFormScreen(existing: _ldapMember), repo: repo),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextFormField, 'Nowe hasło'), findsNothing);
      expect(find.textContaining('loguje się przez katalog'), findsOneWidget);
    });
  });

  group('deleting an account', () {
    Future<({bool deleteItems})?> openDialog(WidgetTester tester) async {
      ({bool deleteItems})? choice;
      await tester.pumpWidget(_app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                choice = await confirmUserDelete(context, _member),
            child: const Text('open'),
          ),
        ),
        repo: repo,
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return choice;
    }

    testWidgets('keeps what the account created unless asked otherwise',
        (tester) async {
      await openDialog(tester);

      expect(find.textContaining('To konto utworzyło 3'), findsOneWidget);
      expect(
        find.textContaining('zostaną, bez właściciela'),
        findsOneWidget,
      );
    });

    testWidgets('carries the choice back to the caller', (tester) async {
      ({bool deleteItems})? choice;
      await tester.pumpWidget(_app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                choice = await confirmUserDelete(context, _member),
            child: const Text('open'),
          ),
        ),
        repo: repo,
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(SwitchListTile, 'Usuń je razem z kontem'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Usuń'));
      await tester.pumpAndSettle();

      expect(choice?.deleteItems, isTrue);
    });

    testWidgets('backing out answers nothing at all', (tester) async {
      ({bool deleteItems})? choice;
      var returned = false;
      await tester.pumpWidget(_app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              choice = await confirmUserDelete(context, _member);
              returned = true;
            },
            child: const Text('open'),
          ),
        ),
        repo: repo,
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Anuluj'));
      await tester.pumpAndSettle();

      expect(returned, isTrue);
      expect(choice, isNull);
    });
  });
}
