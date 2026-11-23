import 'dart:async';
import 'dart:convert';

import 'package:bambuddy_mobile/core/api/edge_access.dart';
import 'package:bambuddy_mobile/core/api/edge_cookie.dart';
import 'package:bambuddy_mobile/core/api/tls_overrides.dart';
import 'package:bambuddy_mobile/core/settings/settings_repository.dart';
import 'package:bambuddy_mobile/features/setup/edge_access_sheet.dart';
import 'package:bambuddy_mobile/features/setup/edge_sign_in_screen.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

// The browser sign-in of Cloudflare Access (#72): the sheet's second way, the
// warning in front of it, the screen that waits for the cookie, and what is
// forgotten when the session goes. The WebView is a stand-in page that says
// when it has loaded; the cookie store is a fake.

const _host = 'printers.example.com';

String _jwt(int exp) {
  String part(Object o) =>
      base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${part({'alg': 'RS256'})}.${part({'exp': exp})}.sig';
}

/// Far ahead of any clock a test runs on, and long past it.
final _valid = _jwt(DateTime.utc(2100).millisecondsSinceEpoch ~/ 1000);
final _ended = _jwt(1);

class _Jar implements EdgeCookieJar {
  _Jar();

  List<String> values = const [];
  var cleared = 0;
  var asked = 0;

  /// Makes the store refuse to be emptied.
  bool failClear = false;

  /// When set, an answer waits for it.
  Completer<void>? gate;

  @override
  Future<List<String>> cookies(Uri url, String name) async {
    asked++;
    final answer = values;
    await gate?.future;
    return answer;
  }

  @override
  Future<void> clear() async {
    cleared++;
    if (failClear) throw StateError('store refused');
  }
}

/// The page stand-in: remembers what it was told to call.
class _Pages {
  var built = 0;
  late VoidCallback loaded;
  late VoidCallback failed;
  Uri? url;

  /// Run as the page is built.
  VoidCallback? onBuild;

  Widget build(
    Uri url, {
    required VoidCallback onLoaded,
    required VoidCallback onFailed,
  }) {
    built++;
    this.url = url;
    loaded = onLoaded;
    failed = onFailed;
    onBuild?.call();
    return const Text('page');
  }
}

void main() {
  late SharedPreferences prefs;
  late ProviderContainer container;
  late _Jar jar;
  late _Pages pages;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    jar = _Jar();
    pages = _Pages();
    addTearDown(() => useTls(null, null));
  });

  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    EdgeAccess? saved,
    double scale = 1.0,
    EdgeAccessStore? store,
  }) async {
    if (saved != null) {
      await EdgeAccessStore().write(saved);
      await SettingsRepository(prefs).saveHasEdgeAccess(true);
    }
    final overrides = <Override>[
      sharedPreferencesProvider.overrideWithValue(prefs),
      initialEdgeAccessProvider.overrideWithValue(saved),
      edgeCookieJarProvider.overrideWithValue(jar),
      edgeSignInPageProvider.overrideWithValue(pages.build),
      if (store != null) edgeAccessStoreProvider.overrideWithValue(store),
    ];
    await pumpPhone(
      tester,
      Consumer(
        builder: (context, ref, _) {
          container = ProviderScope.containerOf(context);
          return home;
        },
      ),
      overrides: overrides,
      builder: textScaled(scale),
    );
  }

  group('the sign-in screen', () {
    /// Pushed from a page behind it, to see what it pops with.
    Future<Future<BrowserSession?>> open(WidgetTester tester) async {
      late BuildContext context;
      await pump(
        tester,
        Scaffold(
          body: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      );
      final result = Navigator.of(context).push<BrowserSession>(
        MaterialPageRoute(builder: (_) => const EdgeSignInScreen(host: _host)),
      );
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('loads the host over https', (tester) async {
      await open(tester);
      expect(pages.url, Uri.parse('https://$_host/'));
    });

    testWidgets('stays while the store holds no session', (tester) async {
      final result = await open(tester);
      var done = false;
      unawaited(result.then((_) => done = true));
      pages.loaded();
      await tester.pumpAndSettle();
      expect(done, isFalse);
      expect(find.text('page'), findsOneWidget);
      expect(jar.asked, 1);
    });

    testWidgets('pops with the session once the cookie is there', (
      tester,
    ) async {
      final result = await open(tester);
      jar.values = [_valid];
      pages.loaded();
      await tester.pumpAndSettle();

      final session = await result;
      expect(session!.host, _host);
      expect(session.cookie, _valid);
      expect(find.text('page'), findsNothing);
    });

    testWidgets('does not take a cookie that has already ended', (
      tester,
    ) async {
      final result = await open(tester);
      var done = false;
      unawaited(result.then((_) => done = true));
      jar.values = [_ended];
      pages.loaded();
      await tester.pumpAndSettle();
      expect(done, isFalse);
    });

    testWidgets('pages finished in one frame pop it once', (tester) async {
      final result = await open(tester);
      jar.values = [_valid];
      pages.loaded();
      pages.loaded();
      pages.loaded();
      await tester.pumpAndSettle();

      expect(await result, isNotNull);
      expect(tester.takeException(), isNull);
      // Popped once: the page behind it is the one left.
      expect(find.byType(EdgeSignInScreen), findsNothing);
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets(
      'a page that finishes while it is closing does not close more',
      (tester) async {
        final result = await open(tester);
        jar.values = [_valid];
        pages.loaded();
        // One frame: the route is on its way out and the screen still mounted.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        pages.loaded();
        await tester.pumpAndSettle();

        expect(await result, isNotNull);
        expect(tester.takeException(), isNull);
        expect(jar.asked, 1, reason: 'the store is not asked again');
        expect(find.byType(Scaffold), findsOneWidget, reason: 'one pop');
      },
    );

    testWidgets('backing out mid-check does not close the page behind', (
      tester,
    ) async {
      final result = await open(tester);
      jar.gate = Completer<void>();
      jar.values = [_valid];
      pages.loaded();
      await tester.pump();
      // Backed out while the store is still being asked.
      // ignore: deprecated_member_use
      await tester.binding.handlePopRoute();
      await tester.pump();
      jar.gate!.complete();
      await tester.pumpAndSettle();

      expect(await result, isNull);
      expect(tester.takeException(), isNull);
      expect(find.byType(Scaffold), findsOneWidget, reason: 'one pop');
    });

    testWidgets('a page that loads after the page failed is not taken', (
      tester,
    ) async {
      final result = await open(tester);
      var done = false;
      unawaited(result.then((_) => done = true));
      jar.values = [_valid];
      pages.failed();
      await tester.pump();
      pages.loaded();
      await tester.pumpAndSettle();

      expect(done, isFalse);
      expect(find.text(pl.edgeAccessSignInFailed), findsOneWidget);
    });

    testWidgets('a page that finishes mid-check is asked about again', (
      tester,
    ) async {
      final result = await open(tester);
      var done = false;
      unawaited(result.then((_) => done = true));
      jar.gate = Completer<void>();
      pages.loaded();
      await tester.pump();
      // The cookie arrives with the next page, while the first answer is out.
      jar.values = [_valid];
      pages.loaded();
      jar.gate!.complete();
      await tester.pumpAndSettle();

      expect(jar.asked, 2);
      expect(done, isTrue);
    });

    testWidgets('a page that cannot load offers to try again', (tester) async {
      await open(tester);
      pages.failed();
      await tester.pump();
      expect(find.text(pl.edgeAccessSignInFailed), findsOneWidget);
      expect(find.text('page'), findsNothing);

      await tester.tap(byLogId('edge_sign_in.retry'));
      await tester.pump();
      expect(pages.built, 2);
      expect(find.text('page'), findsOneWidget);
      expect(find.text(pl.edgeAccessSignInFailed), findsNothing);
    });

    testWidgets('backing out pops with nothing', (tester) async {
      final result = await open(tester);
      // ignore: deprecated_member_use
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(await result, isNull);
    });
  });

  group('the sheet', () {
    late bool? answer;

    Future<void> openSheet(
      WidgetTester tester, {
      EdgeAccess? saved,
      double scale = 1.0,
      EdgeAccessStore? store,
    }) async {
      answer = null;
      await pump(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => answer = await showEdgeAccessSheet(
                context,
                host: _host,
                area: 'setup',
              ),
              child: const Text('open'),
            ),
          ),
        ),
        saved: saved,
        scale: scale,
        store: store,
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    final token = ServiceToken(
      host: _host,
      clientId: 'abc.access',
      clientSecret: 's3cret',
    );
    final session = BrowserSession.fromCookie(host: _host, cookie: _valid)!;

    /// Runs [steps] in a zone that counts what escapes it: the framework fails
    /// a test for an uncaught error, and the app's bug is meant to escape. The
    /// whole flow is inside, because the code after a dialog continues in the
    /// zone of the press that opened it.
    Future<List<Object>> escaping(Future<void> Function() steps) async {
      final reported = <Object>[];
      await runZonedGuarded(steps, (error, _) => reported.add(error));
      return reported;
    }

    VoidCallback onPressed(WidgetTester tester, Finder label) => tester
        .widget<ButtonStyleButton>(
          find.ancestor(
            of: label,
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          ),
        )
        .onPressed!;

    Future<void> chooseBrowser(WidgetTester tester) async {
      await tester.ensureVisible(byLogId('setup.edge_access_method_browser'));
      await tester.tap(byLogId('setup.edge_access_method_browser'));
      await tester.pumpAndSettle();
    }

    Future<void> confirmWarning(WidgetTester tester) async {
      await tester.tap(find.text(pl.edgeAccessWarnConfirm));
      await tester.pumpAndSettle();
    }

    testWidgets('offers the token first, marked as the recommended one', (
      tester,
    ) async {
      await openSheet(tester);
      expect(find.text(pl.edgeAccessRecommended), findsOneWidget);
      expect(byLogId('setup.edge_access_client_id'), findsOneWidget);
      expect(byLogId('setup.edge_access_save'), findsOneWidget);
      expect(byLogId('setup.edge_access_sign_in'), findsNothing);
    });

    testWidgets('the browser way swaps the fields for a button', (
      tester,
    ) async {
      await openSheet(tester);
      await chooseBrowser(tester);
      expect(byLogId('setup.edge_access_client_id'), findsNothing);
      expect(byLogId('setup.edge_access_save'), findsNothing);
      expect(byLogId('setup.edge_access_sign_in'), findsOneWidget);
    });

    testWidgets('warns first, and backing out puts the token back', (
      tester,
    ) async {
      await openSheet(tester);
      await chooseBrowser(tester);
      await tester.tap(byLogId('setup.edge_access_sign_in'));
      await tester.pumpAndSettle();

      expect(find.text(pl.edgeAccessWarnTitle), findsOneWidget);
      expect(pages.built, 0, reason: 'no sign-in before the warning is read');

      await tester.tap(find.text(pl.edgeAccessWarnUseToken));
      await tester.pumpAndSettle();

      expect(pages.built, 0);
      expect(byLogId('setup.edge_access_client_id'), findsOneWidget);
      expect(container.read(edgeAccessProvider), isNull);
    });

    testWidgets('signing in saves the session and closes the sheet', (
      tester,
    ) async {
      await openSheet(tester);
      await chooseBrowser(tester);
      await tester.tap(byLogId('setup.edge_access_sign_in'));
      await tester.pumpAndSettle();
      await confirmWarning(tester);
      expect(find.byType(EdgeSignInScreen), findsOneWidget);

      jar.values = [_valid];
      pages.loaded();
      await tester.pumpAndSettle();

      final saved = container.read(edgeAccessProvider);
      expect(saved, isA<BrowserSession>());
      expect((saved! as BrowserSession).host, _host);
      expect(
        await loadEdgeAccess(SettingsRepository(prefs)),
        saved,
        reason: 'stored, not only held',
      );
      expect(presentedEdgeAccess(), saved);
      expect(find.byType(EdgeSignInScreen), findsNothing);
      expect(find.byType(EdgeAccessSheet), findsNothing);
      expect(answer, isTrue);
    });

    testWidgets('leaving the sign-in leaves the sheet as it was', (
      tester,
    ) async {
      await openSheet(tester);
      await chooseBrowser(tester);
      await tester.tap(byLogId('setup.edge_access_sign_in'));
      await tester.pumpAndSettle();
      await confirmWarning(tester);

      // ignore: deprecated_member_use
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(EdgeAccessSheet), findsOneWidget);
      expect(container.read(edgeAccessProvider), isNull);
      // Released: it can be tried again.
      final again = tester.widget<ButtonStyleButton>(
        find.descendant(
          of: byLogId('setup.edge_access_sign_in'),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        ),
      );
      expect(again.onPressed, isNotNull);
    });

    testWidgets('empties the cookie store before it signs in', (tester) async {
      // Left as it was, the WebView would hand back the cookie it holds, and
      // the sign-in would end before the person had signed in as anyone.
      await openSheet(tester, saved: session);
      var storeWasEmptyWhenOpened = false;
      pages.onBuild = () => storeWasEmptyWhenOpened = jar.cleared == 1;
      await tester.tap(byLogId('setup.edge_access_sign_in'));
      await tester.pumpAndSettle();
      await confirmWarning(tester);

      expect(storeWasEmptyWhenOpened, isTrue);
    });

    testWidgets('a store that cannot be emptied releases the sheet', (
      tester,
    ) async {
      jar.failClear = true;
      await openSheet(tester);
      await chooseBrowser(tester);

      // The app's bug: it escapes, to land in the report as an uncaught error.
      final reported = await escaping(() async {
        onPressed(tester, find.text(pl.edgeAccessSignIn))();
        await tester.pumpAndSettle();
        onPressed(tester, find.text(pl.edgeAccessWarnConfirm))();
        await tester.pumpAndSettle();
      });
      expect(reported, [isA<StateError>()]);
      expect(pages.built, 0);
      final button = tester.widget<ButtonStyleButton>(
        find.descendant(
          of: byLogId('setup.edge_access_sign_in'),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        ),
      );
      expect(button.onPressed, isNotNull, reason: 'released, not locked');
    });

    testWidgets('a removal whose cookie cannot be cleared still closes it', (
      tester,
    ) async {
      jar.failClear = true;
      await openSheet(tester, saved: session);
      final reported = await escaping(() async {
        onPressed(tester, find.text(pl.edgeAccessRemove))();
        await tester.pumpAndSettle();
        onPressed(
          tester,
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text(pl.certificateRemoveConfirm),
          ),
        )();
        await tester.pumpAndSettle();
      });

      // Reported, but after the sheet closed on a credential that is gone: left
      // open it would still offer to remove one.
      expect(reported, [isA<StateError>()]);
      expect(container.read(edgeAccessProvider), isNull, reason: 'removed');
      expect(find.byType(EdgeAccessSheet), findsNothing);
    });

    testWidgets('a route opened over the sheet mid-save does not lock it', (
      tester,
    ) async {
      final store = _GatedStore();
      await openSheet(tester, saved: token, store: store);
      await tester.enterText(
        byLogId('setup.edge_access_client_id'),
        'x.access',
      );
      await tester.enterText(byLogId('setup.edge_access_client_secret'), 'sec');
      await tester.pump();
      await tester.tap(byLogId('setup.edge_access_save'));
      await tester.pump();

      final cover = Navigator.of(
        tester.element(find.byType(EdgeAccessSheet)),
        rootNavigator: true,
      ).push<void>(MaterialPageRoute(builder: (_) => const Text('cover')));
      await tester.pumpAndSettle();
      store.open();
      await tester.pumpAndSettle();
      expect(
        find.byType(EdgeAccessSheet, skipOffstage: false),
        findsOneWidget,
        reason: 'covered',
      );

      Navigator.of(tester.element(find.text('cover'))).pop();
      await tester.pumpAndSettle();
      await cover;
      final save = tester.widget<ButtonStyleButton>(
        find.descendant(
          of: byLogId('setup.edge_access_save'),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        ),
      );
      expect(save.onPressed, isNotNull, reason: 'released, not locked');
    });

    testWidgets('a saved session opens on the browser way', (tester) async {
      await openSheet(tester, saved: session);
      expect(byLogId('setup.edge_access_sign_in'), findsOneWidget);
      expect(byLogId('setup.edge_access_client_id'), findsNothing);
    });

    testWidgets('removing a session forgets the cookie it left', (
      tester,
    ) async {
      await openSheet(tester, saved: session);
      await tester.tap(byLogId('setup.edge_access_remove'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(pl.certificateRemoveConfirm),
        ),
      );
      await tester.pumpAndSettle();

      expect(container.read(edgeAccessProvider), isNull);
      expect(jar.cleared, 1);
    });

    testWidgets('a token that replaces a session forgets its cookie too', (
      tester,
    ) async {
      await openSheet(tester, saved: session);
      await tester.tap(byLogId('setup.edge_access_method_token'));
      await tester.pumpAndSettle();
      await tester.enterText(
        byLogId('setup.edge_access_client_id'),
        'x.access',
      );
      await tester.enterText(byLogId('setup.edge_access_client_secret'), 'sec');
      await tester.pump();
      await tester.tap(byLogId('setup.edge_access_save'));
      await tester.pumpAndSettle();

      expect(container.read(edgeAccessProvider), isA<ServiceToken>());
      expect(jar.cleared, 1);
    });

    testWidgets('removing a token leaves the browser alone', (tester) async {
      await openSheet(tester, saved: token);
      await tester.tap(byLogId('setup.edge_access_remove'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(pl.certificateRemoveConfirm),
        ),
      );
      await tester.pumpAndSettle();

      expect(container.read(edgeAccessProvider), isNull);
      expect(jar.cleared, 0);
    });

    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('fits at text scale $scale, the chip under the title', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(360 * 3, 640 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        await openSheet(tester, scale: scale);
        expect(tester.takeException(), isNull);

        final chip = tester.getRect(find.text(pl.edgeAccessRecommended));
        expect(chip.left, greaterThanOrEqualTo(0));
        expect(chip.right, lessThanOrEqualTo(360));
        await chooseBrowser(tester);
        expect(tester.takeException(), isNull);
      });
    }
  });
}

/// Secure storage whose write of a credential waits for [open].
class _GatedStore extends EdgeAccessStore {
  final _gate = Completer<void>();

  void open() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<void> write(EdgeAccess? access) async {
    if (access != null) await _gate.future;
    await super.write(access);
  }
}
