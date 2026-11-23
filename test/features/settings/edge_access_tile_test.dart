import 'dart:async';

import 'package:bambuddy_mobile/core/api/edge_access.dart';
import 'package:bambuddy_mobile/core/api/tls_overrides.dart';
import 'package:bambuddy_mobile/core/settings/settings_repository.dart';
import 'package:bambuddy_mobile/core/theme/dash_theme.dart';
import 'package:bambuddy_mobile/features/settings/edge_access_tile.dart';
import 'package:bambuddy_mobile/features/setup/edge_access_sheet.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

final _token = ServiceToken(
  host: 'printers.example.com',
  clientId: 'abc.access',
  clientSecret: 's3cret',
);

void main() {
  late SharedPreferences prefs;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    addTearDown(() => useTls(null, null));
  });

  /// Stored as the app would have stored it, so removing has something to remove.
  Future<void> pump(
    WidgetTester tester, {
    EdgeAccess? saved,
    double scale = 1.0,
    List<Override> extra = const [],
  }) async {
    if (saved != null) {
      await EdgeAccessStore().write(saved);
      await SettingsRepository(prefs).saveHasEdgeAccess(true);
    }
    await pumpPhone(
      tester,
      Consumer(
        builder: (context, ref, _) {
          container = ProviderScope.containerOf(context);
          return const Scaffold(
            body: SingleChildScrollView(child: EdgeAccessTile()),
          );
        },
      ),
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        initialEdgeAccessProvider.overrideWithValue(saved),
        ...extra,
      ],
      builder: textScaled(scale),
    );
  }

  final tile = byLogId('app_settings.edge_access');

  /// What a tap calls, called here with no frame between two of them: the
  /// buttons have not been rebuilt disabled yet, as when two taps arrive in one
  /// frame. `tester.tap` pumps between taps and so cannot make that happen.
  VoidCallback pressed(WidgetTester tester, String id) {
    final button = find.descendant(
      of: byLogId(id),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    );
    return tester.widget<ButtonStyleButton>(button).onPressed!;
  }

  testWidgets('is not there while nothing is saved', (tester) async {
    await pump(tester);
    expect(tile, findsNothing);
  });

  testWidgets('says what is saved, and for which host', (tester) async {
    await pump(tester, saved: _token);
    expect(find.text(pl.edgeAccessTitle), findsOneWidget);
    expect(
      find.text(pl.edgeAccessConfigured('printers.example.com')),
      findsOneWidget,
    );
  });

  testWidgets('opens the sheet with the id it was saved with', (tester) async {
    await pump(tester, saved: _token);
    await tester.tap(tile);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'abc.access'), findsOneWidget);
    expect(byLogId('app_settings.edge_access_remove'), findsOneWidget);
  });

  testWidgets('a replacement is stored and presented', (tester) async {
    await pump(tester, saved: _token);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    await tester.enterText(
      byLogId('app_settings.edge_access_client_id'),
      'new.access',
    );
    await tester.enterText(
      byLogId('app_settings.edge_access_client_secret'),
      'new-secret',
    );
    await tester.pump();
    await tester.tap(byLogId('app_settings.edge_access_save'));
    await tester.pumpAndSettle();

    final saved = await loadEdgeAccess(SettingsRepository(prefs));
    expect((saved! as ServiceToken).clientId, 'new.access');
    expect(presentedEdgeAccess(), saved);
  });

  testWidgets('removing asks first, then clears everything', (tester) async {
    await pump(tester, saved: _token);
    await tester.tap(tile);
    await tester.pumpAndSettle();

    await tester.tap(byLogId('app_settings.edge_access_remove'));
    await tester.pumpAndSettle();
    expect(find.text(pl.edgeAccessRemoveTitle), findsOneWidget);
    expect(container.read(edgeAccessProvider), isNotNull, reason: 'not yet');

    // Backing out leaves it.
    await tester.tap(
      find.text(
        MaterialLocalizations.of(
          tester.element(find.byType(AlertDialog)),
        ).cancelButtonLabel,
      ),
    );
    await tester.pumpAndSettle();
    expect(container.read(edgeAccessProvider), isNotNull);

    await tester.tap(byLogId('app_settings.edge_access_remove'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(pl.certificateRemoveConfirm),
      ),
    );
    await tester.pumpAndSettle();

    expect(container.read(edgeAccessProvider), isNull);
    expect(await loadEdgeAccess(SettingsRepository(prefs)), isNull);
    expect(presentedEdgeAccess(), isNull);
    expect(tile, findsNothing);
  });

  testWidgets('a sheet for another host has no remove', (tester) async {
    // The saved credential is for one host; a sheet opened for another is a new
    // set-up, and there is nothing in it to remove.
    await pump(tester, saved: _token);
    final context = tester.element(tile);
    // ignore: unawaited_futures
    showEdgeAccessSheet(
      context,
      host: 'other.example.com',
      area: 'app_settings',
    );
    await tester.pumpAndSettle();
    expect(byLogId('app_settings.edge_access_remove'), findsNothing);
  });

  Future<void> fillAndSave(WidgetTester tester) async {
    await tester.enterText(
      byLogId('app_settings.edge_access_client_id'),
      'new.access',
    );
    await tester.enterText(
      byLogId('app_settings.edge_access_client_secret'),
      'new-secret',
    );
    await tester.pump();
  }

  testWidgets('a double tap on Save writes once', (tester) async {
    final store = _GatedStore();
    await pump(
      tester,
      saved: _token,
      extra: [edgeAccessStoreProvider.overrideWithValue(store)],
    );
    await tester.tap(tile);
    await tester.pumpAndSettle();
    await fillAndSave(tester);

    final save = byLogId('app_settings.edge_access_save');
    // Both taps arrive before the buttons are rebuilt disabled.
    await tester.tap(save);
    await tester.tap(save);
    await tester.pump();
    store.open();
    await tester.pumpAndSettle();

    expect(store.writes, 1);
    expect(find.byType(EdgeAccessSheet), findsNothing);
    expect(tile, findsOneWidget, reason: 'the screen behind is still there');
  });

  testWidgets(
    'a sheet closed under it while it saves does not pop the screen',
    (tester) async {
      final store = _GatedStore();
      await pump(
        tester,
        saved: _token,
        extra: [edgeAccessStoreProvider.overrideWithValue(store)],
      );
      await tester.tap(tile);
      await tester.pumpAndSettle();
      await fillAndSave(tester);
      await tester.tap(byLogId('app_settings.edge_access_save'));
      await tester.pump();

      // Closed from outside, as a drag does, and the write ends before the exit
      // animation has: the sheet is still mounted and no longer the top route.
      Navigator.of(tester.element(find.byType(EdgeAccessSheet))).pop();
      await tester.pump();
      expect(find.byType(EdgeAccessSheet), findsOneWidget);
      store.open();
      await tester.pumpAndSettle();

      expect(find.byType(EdgeAccessSheet), findsNothing);
      expect(tile, findsOneWidget, reason: 'the screen behind is still there');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Remove tapped in the frame of a Save asks nothing', (
    tester,
  ) async {
    // Both taps arrive before the buttons are rebuilt disabled; a confirmation
    // that then deletes what was just saved would undo the Save.
    final store = _GatedStore();
    await pump(
      tester,
      saved: _token,
      extra: [edgeAccessStoreProvider.overrideWithValue(store)],
    );
    await tester.tap(tile);
    await tester.pumpAndSettle();
    await fillAndSave(tester);

    pressed(tester, 'app_settings.edge_access_save')();
    pressed(tester, 'app_settings.edge_access_remove')();
    await tester.pump();

    expect(find.byType(AlertDialog), findsNothing);
    store.open();
    await tester.pumpAndSettle();
    expect(container.read(edgeAccessProvider), isA<ServiceToken>());
  });

  testWidgets('the scrim and the back gesture do not close it while it saves', (
    tester,
  ) async {
    final store = _GatedStore();
    await pump(
      tester,
      saved: _token,
      extra: [edgeAccessStoreProvider.overrideWithValue(store)],
    );
    await tester.tap(tile);
    await tester.pumpAndSettle();
    await fillAndSave(tester);
    await tester.tap(byLogId('app_settings.edge_access_save'));
    await tester.pump();

    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.byType(EdgeAccessSheet), findsOneWidget);
    // ignore: deprecated_member_use
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(EdgeAccessSheet), findsOneWidget);

    store.open();
    await tester.pumpAndSettle();

    expect(find.byType(EdgeAccessSheet), findsNothing);
    expect(tile, findsOneWidget, reason: 'one route popped, not two');
    expect((await store.read() as ServiceToken).clientId, 'new.access');
  });

  testWidgets(
    'a drag can close it, and the save still lands without a second pop',
    (tester) async {
      // A bottom sheet's drag pops its route itself, past any PopScope.
      final store = _GatedStore();
      await pump(
        tester,
        saved: _token,
        extra: [edgeAccessStoreProvider.overrideWithValue(store)],
      );
      await tester.tap(tile);
      await tester.pumpAndSettle();
      await fillAndSave(tester);
      await tester.tap(byLogId('app_settings.edge_access_save'));
      await tester.pump();

      await tester.fling(
        find.byType(EdgeAccessSheet),
        const Offset(0, 600),
        2000,
      );
      // The write finishes while the sheet is still on its way out: it is
      // mounted, and no longer the route on top.
      await tester.pump();
      store.open();
      await tester.pumpAndSettle();
      expect(find.byType(EdgeAccessSheet), findsNothing);

      expect(
        tile,
        findsOneWidget,
        reason: 'the sheet closed once, not the screen',
      );
      expect(tester.takeException(), isNull);
      expect((await store.read() as ServiceToken).clientId, 'new.access');
      expect(container.read(edgeAccessProvider), isA<ServiceToken>());
    },
  );

  testWidgets('a double tap on Remove opens one confirmation', (tester) async {
    await pump(tester, saved: _token);
    await tester.tap(tile);
    await tester.pumpAndSettle();

    final remove = pressed(tester, 'app_settings.edge_access_remove');
    remove();
    remove();
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('Save tapped in the frame of a Remove writes nothing', (
    tester,
  ) async {
    final store = _GatedStore()..open();
    await pump(
      tester,
      saved: _token,
      extra: [edgeAccessStoreProvider.overrideWithValue(store)],
    );
    await tester.tap(tile);
    await tester.pumpAndSettle();
    await fillAndSave(tester);

    pressed(tester, 'app_settings.edge_access_remove')();
    pressed(tester, 'app_settings.edge_access_save')();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(store.writes, 0, reason: 'nothing written behind the dialog');

    // Backing out of the confirmation leaves the sheet usable and the token as
    // it was.
    await tester.tap(
      find.text(
        MaterialLocalizations.of(
          tester.element(find.byType(AlertDialog)),
        ).cancelButtonLabel,
      ),
    );
    await tester.pumpAndSettle();
    expect(container.read(edgeAccessProvider), _token);
    expect(find.byType(EdgeAccessSheet), findsOneWidget);
    await tester.tap(byLogId('app_settings.edge_access_save'));
    await tester.pumpAndSettle();
    expect(store.writes, 1, reason: 'the held sheet was released');
  });

  testWidgets('a double tap on a Save that fails reports it once', (
    tester,
  ) async {
    final store = _FailingStore();
    await pump(
      tester,
      saved: _token,
      extra: [edgeAccessStoreProvider.overrideWithValue(store)],
    );
    await tester.tap(tile);
    await tester.pumpAndSettle();
    await fillAndSave(tester);

    // The failure is the app's bug, so it escapes as an uncaught error and lands
    // in the report; here it is caught as it leaves, to be counted.
    final reported = <Object>[];
    final save = pressed(tester, 'app_settings.edge_access_save');
    await runZonedGuarded(() async {
      save();
      save();
      await tester.pumpAndSettle();
    }, (error, _) => reported.add(error));

    expect(store.attempts, 1);
    expect(reported, [isA<PlatformException>()], reason: 'once, not twice');
    expect(find.byType(EdgeAccessSheet), findsOneWidget, reason: 'released');
  });

  testWidgets('a double tap on the row opens one sheet', (tester) async {
    await pump(tester, saved: _token);
    final open = tester
        .widget<SettingsEntryTile>(find.byType(SettingsEntryTile))
        .onTap;
    open();
    open();
    await tester.pumpAndSettle();

    expect(find.byType(EdgeAccessSheet), findsOneWidget);
  });

  testWidgets(
    'a drag that closes the sheet mid-save still reports the change',
    (tester) async {
      final store = _GatedStore();
      await pump(
        tester,
        saved: _token,
        extra: [edgeAccessStoreProvider.overrideWithValue(store)],
      );
      // Opened as the setup screen opens it, to read what it answers.
      final answer = showEdgeAccessSheet(
        tester.element(tile),
        host: 'printers.example.com',
        area: 'app_settings',
      );
      await tester.pumpAndSettle();
      await fillAndSave(tester);
      await tester.tap(byLogId('app_settings.edge_access_save'));
      await tester.pump();

      Navigator.of(tester.element(find.byType(EdgeAccessSheet))).pop();
      await tester.pumpAndSettle();
      store.open();
      await tester.pumpAndSettle();

      expect(await answer, isTrue);
    },
  );

  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets('fits at text scale $scale', (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 640 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await pump(tester, saved: _token, scale: scale);
      expect(tester.takeException(), isNull);

      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(byLogId('app_settings.edge_access_remove'));
      expect(byLogId('app_settings.edge_access_save'), findsOneWidget);
    });
  }
}

/// Secure storage that refuses every credential and counts the attempts.
class _FailingStore extends EdgeAccessStore {
  var attempts = 0;

  @override
  Future<void> write(EdgeAccess? access) async {
    if (access == null) return super.write(access);
    attempts++;
    throw PlatformException(code: 'keystore');
  }
}

/// Secure storage whose write of a credential waits for [open] and counts them.
class _GatedStore extends EdgeAccessStore {
  final _gate = Completer<void>();
  var writes = 0;

  void open() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<void> write(EdgeAccess? access) async {
    if (access != null) {
      writes++;
      await _gate.future;
    }
    await super.write(access);
  }
}
