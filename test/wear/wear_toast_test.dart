import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:bambuddy_mobile/wear/screens/wear_printer_control_screen.dart';
import 'package:bambuddy_mobile/wear/wear_providers.dart';
import 'package:bambuddy_mobile/wear/wear_shape.dart';
import 'package:bambuddy_mobile/wear/wear_transport.dart';
import 'package:bambuddy_mobile/wear/widgets/wear_screen.dart';
import 'package:bambuddy_mobile/wear/widgets/wear_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// A watch that cannot reach its phone: the failure behind the message this
/// whole layer exists for.
class _TimeoutTransport implements WearTransport {
  @override
  Future<WearFleet> getFleet() async => const WearFleet(
        printers: [
          PrinterWithStatus(
            printer: Printer(id: 7, name: 'X2D-3DP'),
            status: PrinterStatus(
              id: 7,
              connected: true,
              state: 'IDLE',
              awaitingPlateClear: true,
            ),
          ),
        ],
        queuePending: 0,
      );

  @override
  Future<void> clearPlate(int printerId) async => throw WearRelayTimeout();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not this test\'s');
}

class _NoProfileNotifier extends ServerProfileNotifier {
  @override
  ServerProfile? build() => null;
}

/// A bare frame with two buttons that raise a message, for the layer's own
/// behaviour. The screen underneath does not matter here — where the message
/// lands does.
Future<void> _pumpHost(
  WidgetTester tester, {
  Size face = wearFaceSmall,
  WearShape shape = WearShape.round,
  String first = 'Telefon nie odpowiedział',
  String second = 'Płyta zwolniona',
  double textScale = 1,
}) async {
  useWatchFace(tester, shape, face);
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('pl'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: wearShapeBuilder(context, child),
    ),
    home: WearScreen(
      child: Builder(
        builder: (context) {
          hostContext = context;
          return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              onPressed: () =>
                  wearToast(context, first, tone: WearToastTone.failure),
              child: const Text('fail'),
            ),
            TextButton(
              onPressed: () =>
                  wearToast(context, second, tone: WearToastTone.success),
              child: const Text('ok'),
            ),
            ],
          );
        },
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// The screen under the message layer. A test that needs a *second* message
/// cannot tap for it — the first one is covering the buttons, which is the
/// point of the layer.
late BuildContext hostContext;

void main() {
  group('the message layer', () {
    for (final face in [wearFaceSmall, wearFaceLarge]) {
      testWidgets('is readable on a ${face.width.toInt()} px round face',
          (tester) async {
        await _pumpHost(tester, face: face);
        await tester.tap(find.text('fail'));
        await tester.pumpAndSettle();

        // The regression itself: the snackbar this replaced put the same line
        // at the bottom of the square the display reports, where a round face
        // has almost no width left — most of it, and most of the sentence, was
        // off the glass.
        expectOnGlass(tester, find.text('Telefon nie odpowiedział'));
        expectOnGlass(tester, find.text('OK'));
      });
    }

    testWidgets('takes itself away after three seconds', (tester) async {
      await _pumpHost(tester);
      await tester.tap(find.text('fail'));
      await tester.pumpAndSettle();
      expect(find.byType(WearToast), findsOneWidget);

      await tester.pump(wearToastDuration);
      await tester.pump();
      expect(find.byType(WearToast), findsNothing);
    });

    testWidgets('a tap takes it away early, from anywhere on the face',
        (tester) async {
      await _pumpHost(tester);
      await tester.tap(find.text('fail'));
      await tester.pumpAndSettle();

      // Not the word "OK": that is a hint, and the target is the whole face.
      await tester.tapAt(tester.getCenter(find.byType(WearToast)));
      await tester.pumpAndSettle();
      expect(find.byType(WearToast), findsNothing);
    });

    testWidgets('it covers the screen while it is up', (tester) async {
      await _pumpHost(tester);
      await tester.tap(find.text('fail'));
      await tester.pumpAndSettle();

      // A watch screen's buttons all act on the same printer, so a tap meant
      // for the message must not reach the one underneath it.
      await tester.tapAt(tester.getCenter(find.text('ok')));
      await tester.pumpAndSettle();
      expect(find.text('Płyta zwolniona'), findsNothing);
    });

    testWidgets('a second message replaces the first and restarts the clock',
        (tester) async {
      await _pumpHost(tester);
      await tester.tap(find.text('fail'));
      await tester.pumpAndSettle();

      await tester.pump(const Duration(seconds: 2));
      wearToast(hostContext, 'Płyta zwolniona', tone: WearToastTone.success);
      await tester.pumpAndSettle();
      expect(find.text('Telefon nie odpowiedział'), findsNothing);
      expect(find.text('Płyta zwolniona'), findsOneWidget);

      // Past where the first message's own clock would have fired.
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Płyta zwolniona'), findsOneWidget);

      await tester.pump(wearToastDuration);
      await tester.pump();
      expect(find.byType(WearToast), findsNothing);
    });

    testWidgets('a message longer than the face ellipsizes instead of spilling',
        (tester) async {
      await _pumpHost(tester, first: 'Zwolnij płytę. ' * 20);
      await tester.tap(find.text('fail'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // The black layer covers the whole square — it is the *content* that has
      // to stay on the circle.
      expectOnGlass(tester, find.text('Zwolnij płytę. ' * 20));
    });
  });

  testWidgets('at a big system font it drops lines instead of overflowing',
      (tester) async {
    // The size someone who reaches for a watch to avoid squinting will have
    // set. The band the circle allows does not grow with the text, so the
    // message is what has to give.
    await _pumpHost(tester,
        first: 'Zwolnij płytę. ' * 20, textScale: 1.3);
    await tester.tap(find.text('fail'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expectOnGlass(tester, find.text('Zwolnij płytę. ' * 20));
    expectOnGlass(tester, find.text('OK'),
        reason: 'the way out must not be pushed off the glass by the message');
  });

  testWidgets('a failed printer command reaches the wrist readable',
      (tester) async {
    await pumpWear(
      tester,
      const WearPrinterControlScreen(printerId: 7),
      face: wearFaceLarge,
      overrides: [
        serverProfileProvider.overrideWith(_NoProfileNotifier.new),
        wearTransportProvider.overrideWith(
          (ref) => HybridWearTransport(relay: _TimeoutTransport()),
        ),
        requirePlateClearProvider.overrideWith((ref) async => true),
      ],
    );

    await tapOnWatch(tester, find.text('Zwolnij płytę'));
    await tester.pumpAndSettle();

    expect(find.text('Telefon nie odpowiedział'), findsOneWidget);
    expectOnGlass(tester, find.text('Telefon nie odpowiedział'));
  });
}
