import 'dart:convert';

import 'package:bambuddy_mobile/core/api/edge_access.dart';
import 'package:bambuddy_mobile/core/api/edge_cookie.dart';
import 'package:bambuddy_mobile/core/api/tls_overrides.dart';
import 'package:bambuddy_mobile/core/notifications/edge_session_alert.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/core/settings/settings_repository.dart';
import 'package:bambuddy_mobile/features/dashboard/widgets/edge_session_banner.dart';
import 'package:bambuddy_mobile/features/setup/edge_sign_in_screen.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

// The banner for a Cloudflare Access session that ended (#72), and what clears
// it. The sign-in page is a stand-in, the cookie store a fake.

const _host = 'printers.example.com';

String _jwt(int exp) {
  String part(Object o) =>
      base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${part({'alg': 'RS256'})}.${part({'exp': exp})}.sig';
}

final _valid = _jwt(DateTime.utc(2100).millisecondsSinceEpoch ~/ 1000);
final _newer = _jwt(DateTime.utc(2101).millisecondsSinceEpoch ~/ 1000);

class _Jar implements EdgeCookieJar {
  List<String> values = const [];
  var cleared = 0;

  @override
  Future<List<String>> cookies(Uri url, String name) async => values;

  @override
  Future<void> clear() async => cleared++;
}

void main() {
  late SharedPreferences prefs;
  late ProviderContainer container;
  late _Jar jar;
  late VoidCallback pageLoaded;
  var pagesBuilt = 0;

  final session = BrowserSession.fromCookie(host: _host, cookie: _valid)!;
  final token = ServiceToken(
    host: _host,
    clientId: 'abc.access',
    clientSecret: 's3cret',
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    jar = _Jar();
    pagesBuilt = 0;
    addTearDown(() => useTls(null, null));
  });

  Future<void> pump(
    WidgetTester tester, {
    EdgeAccess? saved,
    String? ended,
    double scale = 1.0,
  }) async {
    if (saved != null) {
      await EdgeAccessStore().write(saved);
      await SettingsRepository(prefs).saveHasEdgeAccess(true);
    }
    if (ended != null) {
      await SettingsRepository(prefs).saveEdgeSessionEnded(ended);
    }
    await pumpPhone(
      tester,
      Consumer(
        builder: (context, ref, _) {
          container = ProviderScope.containerOf(context);
          return const Scaffold(body: Column(children: [EdgeSessionBanner()]));
        },
      ),
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        initialEdgeAccessProvider.overrideWithValue(saved),
        edgeCookieJarProvider.overrideWithValue(jar),
        edgeSignInPageProvider.overrideWithValue((
          url, {
          required onLoaded,
          required onFailed,
        }) {
          pagesBuilt++;
          pageLoaded = onLoaded;
          return const Text('page');
        }),
      ],
      builder: textScaled(scale),
    );
  }

  final banner = byLogId('dashboard.edge_session_sign_in');

  testWidgets('is not there while no session has ended', (tester) async {
    await pump(tester, saved: session);
    expect(banner, findsNothing);
  });

  testWidgets('says so once the mark is there', (tester) async {
    await pump(tester, saved: session, ended: _host);
    expect(find.text(pl.edgeSessionBanner), findsOneWidget);
    expect(banner, findsOneWidget);
  });

  testWidgets('says so for a service token too, in its own words', (
    tester,
  ) async {
    await pump(tester, saved: token, ended: _host);
    expect(find.text(pl.edgeTokenBanner), findsOneWidget);
    expect(find.text(pl.edgeSessionBanner), findsNothing);
    expect(byLogId('dashboard.edge_token_replace'), findsOneWidget);
    expect(banner, findsNothing);
  });

  testWidgets('the token one opens the sheet, and replacing it clears it', (
    tester,
  ) async {
    await pump(tester, saved: token, ended: _host);
    await tester.tap(byLogId('dashboard.edge_token_replace'));
    await tester.pumpAndSettle();

    expect(byLogId('dashboard.edge_access_client_id'), findsOneWidget);
    await tester.enterText(
      byLogId('dashboard.edge_access_client_id'),
      'new.access',
    );
    await tester.enterText(
      byLogId('dashboard.edge_access_client_secret'),
      'new-secret',
    );
    await tester.pump();
    await tester.tap(byLogId('dashboard.edge_access_save'));
    await tester.pumpAndSettle();

    expect(
      (container.read(edgeAccessProvider)! as ServiceToken).clientId,
      'new.access',
    );
    expect(SettingsRepository(prefs).loadEdgeSessionEnded(), isNull);
    expect(byLogId('dashboard.edge_token_replace'), findsNothing);
  });

  testWidgets('is not there for a session of another host', (tester) async {
    await pump(tester, saved: session, ended: 'other.example.com');
    expect(banner, findsNothing);
  });

  testWidgets('appears when the app itself finds out', (tester) async {
    await pump(tester, saved: session);
    expect(banner, findsNothing);

    await SettingsRepository(prefs).saveProfile(
      const ServerProfile(baseUrl: 'https://$_host', authMode: AuthMode.none),
    );
    await EdgeSessionAlert(
      settings: () => SettingsRepository(prefs).reloaded(),
    ).ended(_host);
    await tester.pump();

    expect(banner, findsOneWidget);
  });

  testWidgets('goes when Cloudflare accepts the credential again', (
    tester,
  ) async {
    // A refusal that was only for a while must not leave the banner up for a
    // token that works.
    await pump(tester, saved: token, ended: _host);
    expect(byLogId('dashboard.edge_token_replace'), findsOneWidget);

    await tester.runAsync(() async {
      await EdgeSessionAlert(
        settings: () => SettingsRepository(prefs).reloaded(),
      ).accepted(_host);
    });
    await tester.pump();

    expect(byLogId('dashboard.edge_token_replace'), findsNothing);
    expect(SettingsRepository(prefs).loadEdgeSessionEnded(), isNull);
  });

  testWidgets('another host recovering leaves the banner up', (tester) async {
    await pump(tester, saved: token, ended: _host);
    expect(byLogId('dashboard.edge_token_replace'), findsOneWidget);
    // This host's mark is gone from disk, but the app has not been told.
    await SettingsRepository(prefs).saveEdgeSessionEnded(null);

    await tester.runAsync(() async {
      await EdgeSessionAlert(
        settings: () => SettingsRepository(prefs).reloaded(),
      ).accepted('other.example.com');
    });
    await tester.pump();

    expect(byLogId('dashboard.edge_token_replace'), findsOneWidget);
  });

  testWidgets('appears when another isolate wrote it and the app is asked', (
    tester,
  ) async {
    await pump(tester, saved: session);
    await SettingsRepository(prefs).saveEdgeSessionEnded(_host);
    expect(banner, findsNothing, reason: 'nobody has asked yet');

    await container.read(edgeSessionEndedProvider.notifier).refresh();
    await tester.pump();

    expect(banner, findsOneWidget);
  });

  testWidgets('signing in again replaces the session and removes the banner', (
    tester,
  ) async {
    await pump(tester, saved: session, ended: _host);
    await tester.tap(banner);
    await tester.pumpAndSettle();

    expect(jar.cleared, 1, reason: 'a new sign-in, not the refused session');
    expect(find.byType(EdgeSignInScreen), findsOneWidget);

    jar.values = [_newer];
    pageLoaded();
    await tester.pumpAndSettle();

    final saved = container.read(edgeAccessProvider)! as BrowserSession;
    expect(saved.cookie, _newer);
    expect(
      SettingsRepository(prefs).loadEdgeSessionEnded(),
      isNull,
      reason: 'the mark is answered',
    );
    expect(banner, findsNothing);
  });

  testWidgets('saving the very same session again clears it too', (
    tester,
  ) async {
    // An unchanged identity is skipped by the notifier, and must not skip this.
    await pump(tester, saved: session, ended: _host);
    await container.read(tlsIdentityProvider.notifier).setEdge(session);
    await tester.pump();

    expect(SettingsRepository(prefs).loadEdgeSessionEnded(), isNull);
    expect(banner, findsNothing);
  });

  testWidgets('removing the credential clears it', (tester) async {
    await pump(tester, saved: session, ended: _host);
    await container.read(tlsIdentityProvider.notifier).setEdge(null);
    await tester.pump();

    expect(SettingsRepository(prefs).loadEdgeSessionEnded(), isNull);
    expect(banner, findsNothing);
  });

  testWidgets('backing out of the sign-in keeps the banner', (tester) async {
    await pump(tester, saved: session, ended: _host);
    await tester.tap(banner);
    await tester.pumpAndSettle();
    // ignore: deprecated_member_use
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(banner, findsOneWidget);
    expect(container.read(edgeAccessProvider), session);
  });

  testWidgets('two taps in one frame open one sign-in', (tester) async {
    await pump(tester, saved: session, ended: _host);
    final press = tester
        .widget<ButtonStyleButton>(
          find.descendant(
            of: banner,
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          ),
        )
        .onPressed!;
    press();
    press();
    await tester.pumpAndSettle();

    expect(pagesBuilt, 1);
    expect(find.byType(EdgeSignInScreen), findsOneWidget);
  });

  for (final scale in [1.0, 1.5, 2.0]) {
    for (final kind in ['session', 'token']) {
      testWidgets('fits at text scale $scale, for a $kind', (tester) async {
        tester.view.physicalSize = const Size(360 * 3, 640 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        await pump(
          tester,
          saved: kind == 'session' ? session : token,
          ended: _host,
          scale: scale,
        );
        expect(tester.takeException(), isNull);
        final button = byLogId(
          kind == 'session'
              ? 'dashboard.edge_session_sign_in'
              : 'dashboard.edge_token_replace',
        );
        expect(tester.getRect(button).right, lessThanOrEqualTo(360));
        expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
      });
    }
  }
}
