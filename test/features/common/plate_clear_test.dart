import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/features/common/dash_async.dart';
import 'package:bambuddy_mobile/features/common/plate_clear.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  /// The latch reaches the stored profile, so a container has to have one.
  ProviderContainer containerWith([List<Override> overrides = const []]) {
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        ...overrides,
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('isOfflinePlateClearRefusal', () {
    test('the pre-#2864 server insisting on reaching the printer', () {
      expect(isOfflinePlateClearRefusal('Printer not connected'), isTrue);
    });

    test('the current server saying no gate is up is a different answer', () {
      // Same status, opposite meaning: nothing to acknowledge on this printer.
      expect(
        isOfflinePlateClearRefusal(
          'Printer is not awaiting plate-clear acknowledgment (state=IDLE)',
        ),
        isFalse,
      );
    });

    test('a failure the server put no words on is not read as the refusal', () {
      // What the mapper produces when the body carries no `detail` — and what
      // the watch's relay hands over from a phone too old to forward one.
      expect(isOfflinePlateClearRefusal(null), isFalse);
    });

    test('a missing permission is not the refusal', () {
      expect(
        isOfflinePlateClearRefusal(
          "API key does not have 'printers:clear_plate' permission",
        ),
        isFalse,
      );
    });
  });

  group('plateClearPending', () {
    const dirty = PrinterStatus(
      id: 1,
      connected: true,
      awaitingPlateClear: true,
    );

    test('both halves have to agree', () {
      expect(plateClearPending(dirty, gateEnabled: () => true), isTrue);
      // The scheduler does not gate on the plate → nothing to acknowledge.
      expect(plateClearPending(dirty, gateEnabled: () => false), isFalse);
    });

    test('a plate nobody flagged, and a printer with no status at all', () {
      expect(
        plateClearPending(
          const PrinterStatus(id: 1, connected: true),
          gateEnabled: () => true,
        ),
        isFalse,
      );
      // An older server omits the field entirely; unknown is not "waiting".
      expect(plateClearPending(null, gateEnabled: () => true), isFalse);
    });

    test('the server setting is not reached for a plate nobody flagged', () {
      // Why it is a callback: on the phone card it is a `ref.watch` of the
      // server settings, and a card whose plate is clean must not subscribe
      // every printer on the dashboard to that fetch.
      var reads = 0;
      plateClearPending(
        const PrinterStatus(id: 1, connected: true),
        gateEnabled: () {
          reads++;
          return true;
        },
      );
      expect(reads, 0);
    });
  });

  group('the offline-plate-clear latch', () {
    OfflinePlateClearNotifier notifierIn(ProviderContainer c) =>
        c.read(offlinePlateClearProvider.notifier);

    test('starts open, because no version can answer whether #2864 landed', () {
      expect(containerWith().read(offlinePlateClearProvider), isTrue);
    });

    test('a refusal closes it for the rest of the session', () {
      final container = containerWith();

      expect(
        recordPlateClearRefusal(notifierIn(container), 'Printer not connected'),
        isTrue,
      );

      expect(container.read(offlinePlateClearProvider), isFalse);
    });

    test('a failure that is not that refusal leaves it open', () {
      // Only the pre-#2864 wording is evidence. A permission error or a plate
      // nobody flagged must not withdraw a control that works.
      final container = containerWith();

      expect(
        recordPlateClearRefusal(
          notifierIn(container),
          'Printer is not awaiting plate-clear acknowledgment (state=IDLE)',
        ),
        isFalse,
      );

      expect(container.read(offlinePlateClearProvider), isTrue);
    });

    test('the observation does not travel to the next server', () {
      // A different server answers differently, so switching profiles has to
      // start the question over rather than carry one server's "no" to another.
      final container = containerWith();
      recordPlateClearRefusal(notifierIn(container), 'Printer not connected');
      expect(container.read(offlinePlateClearProvider), isFalse);

      container
          .read(serverProfileProvider.notifier)
          .state = const ServerProfile(
        baseUrl: 'http://other.lan:8000',
        authMode: AuthMode.apiKey,
      );

      expect(container.read(offlinePlateClearProvider), isTrue);
    });
  });

  group('plateClearOffered', () {
    Future<ControlOffer> offer(
      WidgetTester tester, {
      required PrinterStatus? status,
      required AsyncValue<bool> gate,
      bool serverRefused = false,
    }) async {
      late ControlOffer result;
      final container = containerWith([
        requirePlateClearProvider.overrideWithValue(gate),
      ]);
      if (serverRefused) {
        recordPlateClearRefusal(
          container.read(offlinePlateClearProvider.notifier),
          'Printer not connected',
        );
      }
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: Consumer(
            builder: (context, ref, _) {
              result = plateClearOffer(ref, status);
              return const SizedBox();
            },
          ),
        ),
      );
      return result;
    }

    Future<bool> offered(
      WidgetTester tester, {
      required PrinterStatus? status,
      required bool gateOn,
      bool serverRefused = false,
    }) async =>
        await offer(
          tester,
          status: status,
          gate: AsyncValue.data(gateOn),
          serverRefused: serverRefused,
        ) ==
        ControlOffer.offered;

    const dirty = PrinterStatus(
      id: 1,
      connected: true,
      awaitingPlateClear: true,
    );
    const dirtyOffline = PrinterStatus(
      id: 1,
      connected: false,
      awaitingPlateClear: true,
    );

    testWidgets('a reachable printer with a dirty plate is offered it', (
      tester,
    ) async {
      expect(await offered(tester, status: dirty, gateOn: true), isTrue);
    });

    testWidgets('an unreachable printer is offered it too', (tester) async {
      // Releasing the gate sends nothing to the machine — it is bambuddy's own
      // flag — and under Auto Power Off "plate dirty, printer off" is how every
      // print ends, so refusing here would strand the commonest case.
      expect(await offered(tester, status: dirtyOffline, gateOn: true), isTrue);
    });

    testWidgets('not once this server has refused the offline release', (
      tester,
    ) async {
      // The button would be dead: a pre-#2864 server wants to reach the printer
      // before it will clear the flag.
      expect(
        await offered(
          tester,
          status: dirtyOffline,
          gateOn: true,
          serverRefused: true,
        ),
        isFalse,
      );
    });

    testWidgets('a reachable printer is still offered it after that refusal', (
      tester,
    ) async {
      // The latch only withdraws the *offline* control.
      expect(
        await offered(tester, status: dirty, gateOn: true, serverRefused: true),
        isTrue,
      );
    });

    testWidgets('nothing is offered when the scheduler does not gate', (
      tester,
    ) async {
      expect(await offered(tester, status: dirty, gateOn: false), isFalse);
    });

    testWidgets('the control waits on screen while the settings are unread', (
      tester,
    ) async {
      // A cold start: the plate is waiting and nothing has said yet whether
      // this server gates on it. Withdrawing the button here takes away the
      // one the user came to the card for.
      expect(
        await offer(tester, status: dirty, gate: const AsyncValue.loading()),
        ControlOffer.pending,
      );
    });

    testWidgets('a settings read that failed is a settled no, not a wait', (
      tester,
    ) async {
      // Otherwise the button sits greyed for the rest of the session with
      // nothing on the card to say why, and no way to retry it.
      expect(
        await offer(
          tester,
          status: dirty,
          gate: AsyncValue.error(StateError('unreadable'), StackTrace.empty),
        ),
        ControlOffer.hidden,
      );
    });

    testWidgets('a clean plate stays hidden even before the settings land', (
      tester,
    ) async {
      expect(
        await offer(
          tester,
          status: const PrinterStatus(id: 1, connected: true),
          gate: const AsyncValue.loading(),
        ),
        ControlOffer.hidden,
      );
    });
  });
}
