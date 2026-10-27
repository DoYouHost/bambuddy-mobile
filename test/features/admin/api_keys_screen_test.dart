import 'package:bambuddy_mobile/core/api/observed_capability.dart';
import 'package:bambuddy_mobile/core/models/api_key.dart';
import 'package:bambuddy_mobile/core/models/current_user.dart';
import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/data/api_keys_repository.dart';
import 'package:bambuddy_mobile/features/admin/api_key_form_screen.dart';
import 'package:bambuddy_mobile/features/admin/api_keys_providers.dart';
import 'package:bambuddy_mobile/features/admin/api_keys_screen.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

final _homeAssistant = ApiKey(
  id: 1,
  name: 'Home Assistant',
  keyPrefix: 'bb_1a2b3c',
  userId: 4,
  scopes: const {ApiKeyScope.readStatus, ApiKeyScope.controlPrinter},
  printerIds: const [2],
  lastUsed: DateTime(2026, 8, 1),
);

const _legacy = ApiKey(
  id: 2,
  name: 'stary skrypt',
  keyPrefix: 'bb_zzzz',
  scopes: {ApiKeyScope.readStatus},
  enabled: false,
);

class _FakeKeys implements ApiKeysRepository {
  _FakeKeys({bool notificationScope = false})
    : notificationScopeCapability = ObservedCapability.unversioned(
        whenUnknown: notificationScope,
      );

  @override
  final ObservedCapability notificationScopeCapability;

  ApiKeyCreateInput? created;
  (int, ApiKeyUpdateInput)? updated;
  int? deleted;

  @override
  Future<List<ApiKey>> list() async => [_homeAssistant, _legacy];

  @override
  Future<CreatedApiKey> create(ApiKeyCreateInput body) async {
    created = body;
    return CreatedApiKey(key: 'bb_pelny_klucz_123', apiKey: _homeAssistant);
  }

  @override
  Future<ApiKey> update(int keyId, ApiKeyUpdateInput body) async {
    updated = (keyId, body);
    return _homeAssistant;
  }

  @override
  Future<void> delete(int keyId) async => deleted = keyId;
}

const _admin = CurrentUser(id: 1, username: 'admin', isAdmin: true);

/// `api_keys:read` and nothing else — the list, no buttons.
const _reader = CurrentUser(
  id: 5,
  username: 'domownik',
  isAdmin: false,
  permissions: {'api_keys:read'},
);

Widget _app(Widget child, {required _FakeKeys repo, CurrentUser? signedInAs}) =>
    ProviderScope(
      retry: neverRetry,
      overrides: [
        apiKeysRepositoryProvider.overrideWithValue(repo),
        currentUserOverride(signedInAs),
        fakeServerProfileOverride(authMode: AuthMode.jwt),
        apiKeyPrinterOptionsProvider.overrideWith(
          (ref) async => const [
            Printer(id: 2, name: 'X1C Warsztat'),
            Printer(id: 3, name: 'A1 mini'),
          ],
        ),
      ],
      child: plApp(child),
    );

void main() {
  late _FakeKeys repo;

  setUp(() => repo = _FakeKeys());

  group('the list', () {
    testWidgets('shows each key by prefix, scopes and state', (tester) async {
      await tester.pumpWidget(
        _app(const ApiKeysScreen(), repo: repo, signedInAs: _admin),
      );
      await tester.pumpAndSettle();

      expect(find.text('Home Assistant'), findsOneWidget);
      expect(find.textContaining('bb_1a2b3c••••'), findsOneWidget);
      expect(find.text(pl.apiKeyScopeRead), findsNWidgets(2));
      expect(find.text(pl.apiKeyScopeControl), findsOneWidget);
      expect(find.text(pl.apiKeysPrinterLimited(1)), findsOneWidget);
      // The switched-off legacy key says both things about itself.
      expect(find.text(pl.apiKeysDisabled), findsOneWidget);
      expect(find.text(pl.apiKeysLegacy), findsOneWidget);
      expect(find.textContaining(pl.apiKeysNeverUsed), findsOneWidget);
    });

    testWidgets('offers no issuing or revoking to a read-only identity', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(const ApiKeysScreen(), repo: repo, signedInAs: _reader),
      );
      await tester.pumpAndSettle();

      expect(find.text(pl.apiKeysCreate), findsNothing);
      expect(find.byTooltip(pl.apiKeysRevoke), findsNothing);
    });

    testWidgets('asks before revoking, and says what that means', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(const ApiKeysScreen(), repo: repo, signedInAs: _admin),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip(pl.apiKeysRevoke).first);
      await tester.pumpAndSettle();

      expect(
        find.text(pl.apiKeysRevokeQuestion('Home Assistant')),
        findsOneWidget,
      );
      expect(find.textContaining(pl.apiKeysRevokeBody), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, pl.apiKeysRevoke));
      await tester.pumpAndSettle();

      expect(repo.deleted, 1);
    });
  });

  group('issuing a key', () {
    testWidgets('starts read-only and sends what was ticked', (tester) async {
      await tester.pumpWidget(
        _app(const ApiKeyFormScreen(), repo: repo, signedInAs: _admin),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, pl.apiKeysFieldName),
        'SpoolBuddy',
      );
      await tester.tap(
        find.widgetWithText(SwitchListTile, pl.apiKeyScopeQueue),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(pl.usersSave));
      await tester.pumpAndSettle();

      expect(repo.created?.name, 'SpoolBuddy');
      expect(repo.created?.scopes, {ApiKeyScope.readStatus, ApiKeyScope.queue});
    });

    testWidgets('offers "send notifications" only where the server has it', (
      tester,
    ) async {
      // Tall enough for every scope row to be built, or the absence below
      // would hold for a row that was merely off screen.
      usePhoneWindow(tester, dp: 2400);
      final notifications = find.widgetWithText(
        SwitchListTile,
        pl.apiKeyScopeNotifications,
      );
      await tester.pumpWidget(
        _app(const ApiKeyFormScreen(), repo: repo, signedInAs: _admin),
      );
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(SwitchListTile, pl.apiKeyScopeEnergy),
        findsOneWidget,
      );
      expect(notifications, findsNothing);

      final current = _FakeKeys(notificationScope: true);
      await tester.pumpWidget(
        _app(
          const ApiKeyFormScreen(key: ValueKey('new')),
          repo: current,
          signedInAs: _admin,
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, pl.apiKeysFieldName),
        'Skrypt',
      );
      await tester.tap(notifications);
      await tester.pumpAndSettle();
      await tester.tap(find.text(pl.usersSave));
      await tester.pumpAndSettle();

      expect(current.created?.scopes, contains(ApiKeyScope.sendNotifications));
    });

    testWidgets('shows the key once, and says it will not come back', (
      tester,
    ) async {
      // The clipboard plugin is not there in a test; swallow the call.
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => null,
      );
      await tester.pumpWidget(
        _app(const ApiKeyFormScreen(), repo: repo, signedInAs: _admin),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, pl.apiKeysFieldName),
        'SpoolBuddy',
      );
      await tester.tap(find.text(pl.usersSave));
      await tester.pumpAndSettle();

      expect(find.text('bb_pelny_klucz_123'), findsOneWidget);
      expect(find.textContaining(pl.apiKeysCreatedWarning), findsOneWidget);

      await tester.tap(find.text(pl.apiKeysCopy));
      await tester.pumpAndSettle();
    });

    testWidgets('confines a key to chosen printers', (tester) async {
      // Tall enough for the form's own height in the app theme.
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(const ApiKeyFormScreen(), repo: repo, signedInAs: _admin),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, pl.apiKeysFieldName),
        'Warsztat',
      );
      // The form is a long list on a phone-sized screen; the printer section
      // is below the fold and not built until it scrolls into view.
      await tester.dragUntilVisible(
        find.widgetWithText(SwitchListTile, pl.apiKeysAllPrinters),
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.tap(
        find.widgetWithText(SwitchListTile, pl.apiKeysAllPrinters),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('A1 mini'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(pl.usersSave));
      await tester.pumpAndSettle();

      expect(repo.created?.printerIds, [3]);
    });
  });

  group('editing a key', () {
    testWidgets('a key holding "send notifications" keeps its switch', (
      tester,
    ) async {
      usePhoneWindow(tester, dp: 2400);
      await tester.pumpWidget(
        _app(
          ApiKeyFormScreen(
            existing: ApiKey(
              id: 9,
              name: 'n8n',
              keyPrefix: 'bb_n8n',
              scopes: const {ApiKeyScope.sendNotifications},
            ),
          ),
          repo: repo,
          signedInAs: _admin,
        ),
      );
      await tester.pumpAndSettle();

      final notifications = find.widgetWithText(
        SwitchListTile,
        pl.apiKeyScopeNotifications,
      );
      expect(notifications, findsOneWidget);

      // Cleared, it stays where it was, so the tap can be undone.
      await tester.tap(notifications);
      await tester.pumpAndSettle();
      expect(notifications, findsOneWidget);
      await tester.tap(find.text(pl.usersSave));
      await tester.pumpAndSettle();
      expect(
        repo.updated?.$2.scopes,
        isNot(contains(ApiKeyScope.sendNotifications)),
      );
    });

    testWidgets('sends only what changed', (tester) async {
      await tester.pumpWidget(
        _app(
          ApiKeyFormScreen(existing: _homeAssistant),
          repo: repo,
          signedInAs: _admin,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(SwitchListTile, pl.apiKeysFieldEnabled),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(pl.usersSave));
      await tester.pumpAndSettle();

      expect(repo.updated?.$1, 1);
      expect(repo.updated?.$2.enabled, isFalse);
      expect(repo.updated?.$2.name, isNull);
      expect(repo.updated?.$2.scopes, isNull);
    });

    testWidgets('lifting a printer limit sends an explicit null', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          ApiKeyFormScreen(existing: _homeAssistant),
          repo: repo,
          signedInAs: _admin,
        ),
      );
      await tester.pumpAndSettle();

      // The form is a long list on a phone-sized screen; the printer section
      // is below the fold and not built until it scrolls into view.
      await tester.dragUntilVisible(
        find.widgetWithText(SwitchListTile, pl.apiKeysAllPrinters),
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.tap(
        find.widgetWithText(SwitchListTile, pl.apiKeysAllPrinters),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(pl.usersSave));
      await tester.pumpAndSettle();

      // Omitting the field would mean "unchanged", which is the opposite.
      expect(repo.updated?.$2.toJson().containsKey('printer_ids'), isTrue);
      expect(repo.updated?.$2.toJson()['printer_ids'], isNull);
    });
  });
}
