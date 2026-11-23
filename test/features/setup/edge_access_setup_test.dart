import 'dart:convert';
import 'dart:typed_data';

import 'package:bambuddy_mobile/core/api/api_client.dart';
import 'package:bambuddy_mobile/core/api/edge_access.dart';
import 'package:bambuddy_mobile/core/api/tls_overrides.dart';
import 'package:bambuddy_mobile/features/setup/providers.dart';
import 'package:bambuddy_mobile/features/setup/setup_screen.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

// The setup screen of a server behind Cloudflare Access (#72): the probe ends on
// the sign-in page, the screen offers to set it up, and what is saved there is
// what the next probe presents.

const _login = 'https://team.cloudflareaccess.com/cdn-cgi/access/login/x';
const _url = 'https://printers.example.com';

/// How the server answers: [behind] is Cloudflare in front, which lets a
/// request through only when it presents a credential; [refusing] is Cloudflare
/// in front that accepts nothing the app presents; [plain] is no Cloudflare;
/// [down] is nothing answering at all.
enum _Mode { behind, refusing, plain, down }

class _Server implements HttpClientAdapter {
  _Server(this.mode, {this.via});

  final _Mode mode;

  /// A host the request is sent on to before Cloudflare, as an alias is.
  final String? via;

  /// The host of each request, in order.
  final hosts = <String>[];
  var calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    hosts.add(options.uri.host);
    if (mode == _Mode.down) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'no route',
      );
    }
    final signIn =
        mode == _Mode.refusing ||
        (mode == _Mode.behind && presentedEdgeAccess() == null);
    if (signIn) {
      return ResponseBody.fromString(
          '<html>Sign in</html>',
          200,
          headers: {
            Headers.contentTypeHeader: ['text/html'],
          },
        )
        ..redirects = [
          if (via != null)
            RedirectRecord(301, 'GET', Uri.parse('https://$via/')),
          RedirectRecord(302, 'GET', Uri.parse(_login)),
        ];
    }
    final version = options.uri.path.endsWith('/updates/version');
    return ResponseBody.fromString(
      jsonEncode(
        version
            ? {'version': '1.3.0', 'repo': 'maziggy/bambuddy'}
            : {'auth_enabled': true, 'requires_setup': false},
      ),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late SharedPreferences prefs;
  late ProviderContainer container;
  late _Server server;
  var mode = _Mode.behind;
  String? via;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    mode = _Mode.behind;
    via = null;
    addTearDown(() => useTls(null, null));
  });

  Future<void> pump(WidgetTester tester, {double scale = 1.0}) async {
    server = _Server(mode, via: via);
    final dio = createBareDio()..httpClientAdapter = server;
    await pumpPhone(
      tester,
      Consumer(
        builder: (context, ref, _) {
          container = ProviderScope.containerOf(context);
          return const SetupScreen();
        },
      ),
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        noServerProfileOverride,
        credentialsStoreProvider.overrideWithValue(InMemoryCredentialsStore()),
        bareDioProvider.overrideWithValue(dio),
      ],
      builder: textScaled(scale),
    );
    await tester.pump();
  }

  Future<void> probe(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField).first, _url);
    await tester.tap(byLogId('setup.test_connection'));
    await tester.pumpAndSettle();
  }

  final setUp_ = byLogId('setup.edge_access_set_up');
  final idField = byLogId('setup.edge_access_client_id');
  final secretField = byLogId('setup.edge_access_client_secret');
  final save = byLogId('setup.edge_access_save');

  bool saveEnabled(WidgetTester tester) =>
      tester
          .widget<FilledButton>(
            find.descendant(of: save, matching: find.byType(FilledButton)),
          )
          .onPressed !=
      null;

  testWidgets('a server behind Cloudflare Access is offered the set-up', (
    tester,
  ) async {
    await pump(tester);
    await probe(tester);

    expect(find.text(pl.errEdgeAccessRequired), findsOneWidget);
    expect(setUp_, findsOneWidget);
    expect(find.text(pl.errNotBambuddy), findsNothing);
  });

  testWidgets('an alias binds the credential to the host Cloudflare guards', (
    tester,
  ) async {
    // The address typed redirects to its canonical host first, and it is that
    // host that every later request goes to.
    via = 'www.example.com';
    await pump(tester);
    await probe(tester);

    await tester.tap(setUp_);
    await tester.pumpAndSettle();
    expect(find.text(pl.edgeAccessFor('www.example.com')), findsOneWidget);
    await tester.enterText(idField, 'abc.access');
    await tester.enterText(secretField, 's3cret');
    await tester.pump();
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(container.read(edgeAccessProvider)!.host, 'www.example.com');
  });

  testWidgets('a server that is not behind it shows no such offer', (
    tester,
  ) async {
    mode = _Mode.plain;
    await pump(tester);
    await probe(tester);

    expect(setUp_, findsNothing);
    expect(container.read(setupControllerProvider).probe, isNotNull);
  });

  testWidgets('the same token typed again asks the server again', (
    tester,
  ) async {
    // Once the policy is fixed on the Cloudflare side, the token that was
    // refused is the right one: nothing changes in the app, and the server is
    // still asked.
    mode = _Mode.refusing;
    await pump(tester);
    await probe(tester);

    Future<void> setUpWithToken() async {
      await tester.tap(setUp_);
      await tester.pumpAndSettle();
      await tester.enterText(idField, 'abc.access');
      await tester.enterText(secretField, 's3cret');
      await tester.pump();
      await tester.tap(save);
      await tester.pumpAndSettle();
    }

    await setUpWithToken();
    final before = server.calls;
    await setUpWithToken();

    expect(server.calls, greaterThan(before));
  });

  testWidgets(
    'asks about the address that was probed, not the one edited since',
    (tester) async {
      await pump(tester);
      await probe(tester);
      server.hosts.clear();

      await tester.enterText(
        find.byType(TextField).first,
        'https://elsewhere.example.org',
      );
      await tester.tap(setUp_);
      await tester.pumpAndSettle();
      await tester.enterText(idField, 'abc.access');
      await tester.enterText(secretField, 's3cret');
      await tester.pump();
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(server.hosts, isNotEmpty);
      expect(server.hosts.toSet(), {'printers.example.com'});
    },
  );

  testWidgets('a server that does not answer gets no such offer either', (
    tester,
  ) async {
    mode = _Mode.down;
    await pump(tester);
    await probe(tester);

    expect(find.text(pl.errServerUnreachable), findsOneWidget);
    expect(setUp_, findsNothing);
  });

  testWidgets('saving the token asks the server again with it', (tester) async {
    await pump(tester);
    await probe(tester);
    final before = server.calls;

    await tester.tap(setUp_);
    await tester.pumpAndSettle();
    expect(find.text(pl.edgeAccessFor('printers.example.com')), findsOneWidget);
    expect(saveEnabled(tester), isFalse);

    await tester.enterText(idField, '  abc.access ');
    await tester.pump();
    expect(saveEnabled(tester), isFalse, reason: 'the secret is missing');
    await tester.enterText(secretField, ' s3cret ');
    await tester.pump();
    expect(saveEnabled(tester), isTrue);

    await tester.tap(save);
    await tester.pumpAndSettle();

    final saved = container.read(edgeAccessProvider);
    expect(saved, isA<ServiceToken>());
    expect((saved! as ServiceToken).clientId, 'abc.access');
    expect((saved as ServiceToken).clientSecret, 's3cret');
    expect(saved.host, 'printers.example.com');
    expect(server.calls, greaterThan(before), reason: 'probed again');
    expect(setUp_, findsNothing);
    expect(find.text(pl.errEdgeAccessRequired), findsNothing);
    expect(container.read(setupControllerProvider).probe, isNotNull);
  });

  testWidgets('a token Cloudflare refuses is reported, and can be replaced', (
    tester,
  ) async {
    mode = _Mode.refusing;
    await pump(tester);
    await probe(tester);
    expect(find.text(pl.errEdgeAccessRequired), findsOneWidget);

    await tester.tap(setUp_);
    await tester.pumpAndSettle();
    await tester.enterText(idField, 'abc.access');
    await tester.enterText(secretField, 'wrong');
    await tester.pump();
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(find.text(pl.errEdgeAccessRejected), findsOneWidget);
    expect(find.text(pl.errEdgeAccessRequired), findsNothing);
    // The offer stays, and the id is what the person recognises it by.
    await tester.tap(setUp_);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'abc.access'), findsOneWidget);
    expect(saveEnabled(tester), isFalse, reason: 'the secret is typed again');
  });

  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets('the sheet fits at text scale $scale', (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 640 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await pump(tester, scale: scale);
      await probe(tester);

      await tester.ensureVisible(setUp_);
      await tester.tap(setUp_);
      await tester.pumpAndSettle();
      await tester.enterText(idField, 'abc.access');
      await tester.enterText(secretField, 's3cret');
      await tester.pump();

      expect(tester.takeException(), isNull);
      // Reachable without scrolling the page behind: the sheet scrolls itself.
      await tester.ensureVisible(save);
      expect(save, findsOneWidget);
      expect(saveEnabled(tester), isTrue);
    });
  }
}
