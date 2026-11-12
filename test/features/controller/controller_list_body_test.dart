import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/features/controller/controller_list_parts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers.dart';

/// A list the test steers through "answered", "failed" and "failed, retry under
/// way". Assigning to `state` is what the real notifiers do: Riverpod keeps the
/// last value (and the failure) on the next loading state.
class _Steered extends AsyncNotifier<List<String>> {
  @override
  Future<List<String>> build() async => ['tile'];

  void fail() {
    final failure = AsyncError<List<String>>(
      const ApiException(AppErrorCode.connectionError),
      StackTrace.empty,
    );
    state = failure;
  }

  void load() => state = const AsyncLoading<List<String>>();
}

final _list = AsyncNotifierProvider<_Steered, List<String>>(_Steered.new);

void main() {
  Future<ProviderContainer> open(
    WidgetTester tester,
    ControllerListFailureMode mode, {
    bool answered = true,
  }) async {
    await pumpPhone(
      tester,
      Consumer(
        builder: (context, ref, _) {
          final async = ref.watch(_list);
          return Column(
            children: [
              ControllerListBody<List<String>>(
                async: async,
                value: answered ? async.value : null,
                retryId: 'test.retry',
                onRetry: () {},
                onFailure: mode,
                grid: (items) => Text(items.join(',')),
              ),
            ],
          );
        },
      ),
    );
    await settle(tester);
    return ProviderScope.containerOf(tester.element(find.byType(Consumer)));
  }

  Future<void> step(
    WidgetTester tester,
    ProviderContainer c,
    void Function(_Steered n) change,
  ) async {
    change(c.read(_list.notifier));
    await tester.pump();
  }

  final failure = find.text(pl.connectFailed);
  final tile = find.text('tile');
  final spinner = find.byType(CircularProgressIndicator);

  group('below', () {
    testWidgets('keeps the tiles and the failure through a retry', (
      tester,
    ) async {
      final c = await open(tester, ControllerListFailureMode.below);
      await step(tester, c, (n) => n.fail());
      expect(tile, findsOneWidget);
      expect(failure, findsOneWidget);

      await step(tester, c, (n) => n.load());
      expect(tile, findsOneWidget);
      expect(failure, findsOneWidget, reason: 'it must not blink out and back');
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });
  });

  group('hidden', () {
    testWidgets('keeps the tiles and says nothing', (tester) async {
      final c = await open(tester, ControllerListFailureMode.hidden);
      await step(tester, c, (n) => n.fail());
      expect(tile, findsOneWidget);
      expect(failure, findsNothing);

      await step(tester, c, (n) => n.load());
      expect(tile, findsOneWidget);
      expect(failure, findsNothing);
    });
  });

  group('replace', () {
    testWidgets('the failure takes the tiles, and a retry is a spinner, not '
        'the old tiles', (tester) async {
      final c = await open(tester, ControllerListFailureMode.replace);
      await step(tester, c, (n) => n.fail());
      expect(tile, findsNothing);
      expect(failure, findsOneWidget);

      await step(tester, c, (n) => n.load());
      expect(tile, findsNothing, reason: 'the old answer would mislead');
      expect(failure, findsNothing);
      expect(spinner, findsOneWidget);
    });
  });

  testWidgets('with nothing to keep, a failure is the whole card in any mode', (
    tester,
  ) async {
    for (final mode in ControllerListFailureMode.values) {
      final c = await open(tester, mode, answered: false);
      await step(tester, c, (n) => n.fail());
      expect(failure, findsOneWidget, reason: '$mode');
      expect(tile, findsNothing, reason: '$mode');

      await step(tester, c, (n) => n.load());
      expect(spinner, findsOneWidget, reason: '$mode');
      expect(failure, findsNothing, reason: '$mode');
    }
  });

  testWidgets('a refusal has nothing to retry', (tester) async {
    await pumpPhone(
      tester,
      const Column(
        children: [
          ControllerListFailure(
            error: AuthException(AppErrorCode.forbidden),
            retryId: 'test.retry',
            onRetry: _noop,
          ),
        ],
      ),
    );
    await settle(tester);
    expect(byLogId('test.retry'), findsNothing);
  });
}

void _noop() {}
