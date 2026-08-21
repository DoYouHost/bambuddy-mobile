import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/features/common/dash_async.dart';
import 'package:bambuddy_mobile/features/common/dash_progress.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/l10n/error_messages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
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
