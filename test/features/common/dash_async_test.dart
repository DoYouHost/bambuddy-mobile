import 'package:dash_kit/dash_kit.dart';
import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/features/common/dash_async.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/l10n/error_messages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bambuddy_mobile/core/api/server_reachability.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
  /// One decision, previously spelled two ways across nineteen call sites.
  /// Every one of them gates a control, so what matters is that the three
  /// non-answers — loading, error, and a refusal the server has not sent yet —
  /// all read as off, and that no call site can accidentally write the
  /// opposite.
  group('orFalse', () {
    test('only a true answer is on', () {
      expect(const AsyncValue.data(true).orFalse, isTrue);
      expect(const AsyncValue.data(false).orFalse, isFalse);
    });

    test('a gate still loading is off, not on', () {
      // Otherwise a drawer entry flashes in and out, or a button leads to a
      // route the server turns out not to have.
      expect(const AsyncValue<bool>.loading().orFalse, isFalse);
    });

    test('a gate that failed to load is off', () {
      expect(
        AsyncValue<bool>.error(Exception('no'), StackTrace.empty).orFalse,
        isFalse,
      );
    });

    test('a refresh keeps answering with the value it already had', () {
      // `AsyncLoading.copyWithPrevious` is how a pull-to-refresh reports
      // itself; a control must not blink off underneath the user for it.
      const settled = AsyncValue.data(true);
      final refreshing = const AsyncValue<bool>.loading().copyWithPrevious(
        settled,
      );

      expect(refreshing.orFalse, isTrue);
    });
  });

  late int retries;

  Future<AppLocalizations> pumpState(
    WidgetTester tester,
    AsyncValue<String> value,
  ) async {
    retries = 0;
    late AppLocalizations l10n;
    await tester.pumpWidget(
      plApp(
        Builder(
          builder: (context) {
            l10n = AppLocalizations.of(context);
            return Scaffold(
              body: dashAsync(
                context,
                value,
                onRetry: () => retries++,
                data: (text) => Text(text),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();
    return l10n;
  }

  testWidgets('waiting shows the spinner and nothing else', (tester) async {
    await pumpState(tester, const AsyncValue<String>.loading());

    expect(find.byType(DashLoading), findsOneWidget);
  });

  testWidgets('a server already known to be out of reach skips the wait', (
    tester,
  ) async {
    // The whole point of the shared answer: the second screen the user opens
    // says so at once instead of spinning through its own connect timeout.
    ServerReachability.instance.reachable.value = false;
    addTearDown(ServerReachability.instance.forget);

    final l10n = await pumpState(tester, const AsyncValue<String>.loading());

    expect(find.byType(DashLoading), findsNothing);
    expect(find.text(l10n.connectFailed), findsOneWidget);
    await tester.tap(find.text(l10n.retry));
    expect(retries, 1);
  });

  testWidgets('retrying shows the spinner rather than a dead button', (
    tester,
  ) async {
    // The shared answer is still "unreachable" while the retry is in flight,
    // so without forgetting it first the screen would keep the error up and
    // the button would look like it did nothing.
    ServerReachability.instance.reachable.value = false;
    addTearDown(ServerReachability.instance.forget);
    final l10n = await pumpState(tester, const AsyncValue<String>.loading());

    await tester.tap(find.text(l10n.retry));
    await tester.pump();

    expect(retries, 1);
    expect(find.byType(DashLoading), findsOneWidget);
  });

  testWidgets('the server coming back fetches again, with no pull needed', (
    tester,
  ) async {
    // Only the dashboard recovered by itself, because it polls. Every other
    // tab kept the failure it had collected in flight mode.
    ServerReachability.instance.reachable.value = false;
    addTearDown(ServerReachability.instance.forget);
    await pumpState(
      tester,
      AsyncValue<String>.error(
        const NetworkException(AppErrorCode.serverUnreachable),
        StackTrace.empty,
      ),
    );
    expect(retries, 0);

    ServerReachability.instance.reachable.value = true;
    await tester.pump();

    expect(retries, 1);
  });

  testWidgets('a request still in the air is left to finish', (tester) async {
    // It may be the one that brings the server back. A second alongside it is
    // two requests and a race over which answer the provider keeps.
    ServerReachability.instance.reachable.value = false;
    addTearDown(ServerReachability.instance.forget);
    await pumpState(tester, const AsyncValue<String>.loading());

    ServerReachability.instance.reachable.value = true;
    await tester.pump();

    expect(retries, 0);
  });

  testWidgets('a failure that lands after the server returned is retried', (
    tester,
  ) async {
    // The connect timeout of a request started in flight mode expires long
    // after the radio is back; the screen must not keep its verdict.
    ServerReachability.instance.reachable.value = false;
    addTearDown(ServerReachability.instance.forget);
    await pumpState(tester, const AsyncValue<String>.loading());
    ServerReachability.instance.reachable.value = true;
    await tester.pump();
    expect(retries, 0);

    await pumpState(
      tester,
      AsyncValue<String>.error(
        const NetworkException(AppErrorCode.serverUnreachable),
        StackTrace.empty,
      ),
    );
    await tester.pump();

    expect(retries, 1);
  });

  testWidgets('a failure of the server itself is not asked again', (
    tester,
  ) async {
    // A 500 is an answer. Asking every screen again the moment the radio comes
    // back would be a request each for a state nothing has changed about.
    ServerReachability.instance.reachable.value = false;
    addTearDown(ServerReachability.instance.forget);
    await pumpState(
      tester,
      AsyncValue<String>.error(
        const ApiException(AppErrorCode.badResponse, statusCode: 500),
        StackTrace.empty,
      ),
    );

    ServerReachability.instance.reachable.value = true;
    await tester.pump();

    expect(retries, 0);
  });

  testWidgets('a screen opened after the server came back asks once', (
    tester,
  ) async {
    ServerReachability.instance.reachable.value = true;
    addTearDown(ServerReachability.instance.forget);

    await pumpState(
      tester,
      AsyncValue<String>.error(
        const NetworkException(AppErrorCode.serverUnreachable),
        StackTrace.empty,
      ),
    );
    await tester.pump();

    expect(retries, 1);
  });

  testWidgets('a server that has answered is waited for', (tester) async {
    ServerReachability.instance.reachable.value = true;
    addTearDown(ServerReachability.instance.forget);

    await pumpState(tester, const AsyncValue<String>.loading());

    expect(find.byType(DashLoading), findsOneWidget);
  });

  testWidgets('data on screen outlives the server going away', (tester) async {
    // A list already fetched stays: the failure belongs to the next request,
    // not to what the user is looking at.
    ServerReachability.instance.reachable.value = false;
    addTearDown(ServerReachability.instance.forget);

    await pumpState(
      tester,
      const AsyncValue<String>.loading().copyWithPrevious(
        const AsyncValue.data('seventeen spools'),
      ),
    );

    expect(find.text('seventeen spools'), findsOneWidget);
  });

  testWidgets('data is the only branch a screen writes', (tester) async {
    await pumpState(tester, const AsyncValue<String>.data('seventeen spools'));

    expect(find.text('seventeen spools'), findsOneWidget);
    expect(find.byType(DashLoading), findsNothing);
  });

  testWidgets('a refused request is worded by the server, and retried', (
    tester,
  ) async {
    const failure = NetworkException(AppErrorCode.serverUnreachable);
    final l10n = await pumpState(
      tester,
      AsyncValue<String>.error(failure, StackTrace.empty),
    );

    expect(find.text(failure.localized(l10n)), findsOneWidget);

    await tester.tap(find.text(l10n.retry));
    expect(retries, 1);
  });

  testWidgets('anything that is not a server answer still offers a retry', (
    tester,
  ) async {
    final l10n = await pumpState(
      tester,
      AsyncValue<String>.error(StateError('boom'), StackTrace.empty),
    );

    expect(find.text(l10n.connectFailed), findsOneWidget);
    expect(find.text(l10n.retry), findsOneWidget);
  });

  group('a section rather than a screen', () {
    Future<AppLocalizations> pumpStrip(
      WidgetTester tester,
      AsyncValue<String> value, {
      double? height,
      String? failureMessage,
    }) async {
      late AppLocalizations l10n;
      await tester.pumpWidget(
        plApp(
          Builder(
            builder: (context) {
              l10n = AppLocalizations.of(context);
              return Scaffold(
                body: dashAsyncStrip(
                  context,
                  value,
                  height: height,
                  failureMessage: failureMessage,
                  data: (text) => Text(text),
                ),
              );
            },
          ),
        ),
      );
      await tester.pump();
      return l10n;
    }

    testWidgets('waiting and failing keep the height the content will have', (
      tester,
    ) async {
      for (final state in <AsyncValue<String>>[
        const AsyncValue.loading(),
        AsyncValue.error(StateError('boom'), StackTrace.empty),
      ]) {
        await pumpStrip(tester, state, height: 120);
        expect(tester.getSize(find.byType(SizedBox).first).height, 120);
      }

      // The data branch sizes itself — that is the height the other two were
      // standing in for.
      await pumpStrip(tester, const AsyncValue.data('done'), height: 120);
      expect(find.text('done'), findsOneWidget);
      expect(find.byType(SizedBox), findsNothing);
    });

    testWidgets('says the section words its own failure', (tester) async {
      await pumpStrip(
        tester,
        AsyncValue<String>.error(StateError('boom'), StackTrace.empty),
        failureMessage: 'no readings yet',
      );

      expect(find.text('no readings yet'), findsOneWidget);
    });

    testWidgets('but still quotes the server when the server answered', (
      tester,
    ) async {
      const failure = NetworkException(AppErrorCode.serverUnreachable);
      final l10n = await pumpStrip(
        tester,
        AsyncValue<String>.error(failure, StackTrace.empty),
        failureMessage: 'no readings yet',
      );

      expect(find.text(failure.localized(l10n)), findsOneWidget);
    });
  });
}
