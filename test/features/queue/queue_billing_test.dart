import 'dart:async';

import 'package:bambuddy_mobile/core/ams/job_cost.dart';
import 'package:bambuddy_mobile/core/models/cost_center.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:bambuddy_mobile/features/orders/orders_providers.dart';
import 'package:bambuddy_mobile/features/queue/job_cost_providers.dart';
import 'package:bambuddy_mobile/features/queue/queue_edit_screen.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';
import 'queue_form_harness.dart';

/// A billing server refuses a queue create, edit and start without a cost
/// center (maziggy/bambuddy #3256): the form offers the user's own to pick from,
/// and where there are none says so up front instead of sending what will be
/// refused.
/// The cost center select; the printer select beside it is a `DropdownMenu<int>` too.
final _costCenterField = find.descendant(
  of: byLogId('queue_edit.cost_center'),
  matching: find.byType(DropdownMenu<int>),
);

void main() {
  setUp(setUpQueueForm);

  bool billing({Map<String, dynamic>? flags, Map<String, dynamic>? settings}) {
    final container = ProviderContainer(
      retry: neverRetry,
      overrides: [
        serverUiFlagsProvider.overrideWith((ref) async => flags ?? const {}),
        serverSettingsOverride(settings ?? const {}),
      ],
    );
    addTearDown(container.dispose);
    container
      ..listen(serverUiFlagsProvider, (_, _) {})
      ..listen(serverSettingsProvider, (_, _) {});
    return container.read(billingEnabledProvider);
  }

  test(
    'the UI flags answer first, the full settings on an older server',
    () async {
      Future<bool> settled({
        Map<String, dynamic>? flags,
        Map<String, dynamic>? settings,
      }) async {
        final container = ProviderContainer(
          retry: neverRetry,
          overrides: [
            serverUiFlagsProvider.overrideWith(
              (ref) async => flags ?? const {},
            ),
            serverSettingsOverride(settings ?? const {}),
          ],
        );
        addTearDown(container.dispose);
        await container.read(serverUiFlagsProvider.future);
        await container.read(serverSettingsProvider.future);
        return container.read(billingEnabledProvider);
      }

      expect(await settled(flags: {'billing_enabled': true}), isTrue);
      // A non-admin's settings read is refused, so only the flags know.
      expect(
        await settled(flags: {'billing_enabled': true}, settings: const {}),
        isTrue,
      );
      expect(await settled(settings: {'billing_enabled': true}), isTrue);
      expect(await settled(flags: {'billing_enabled': false}), isFalse);
      expect(await settled(), isFalse);
      expect(billing(), isFalse, reason: 'false until either answers');
    },
  );

  test('the flag is read afresh for the next screen that asks', () async {
    // Switched on in the web while the app runs, or a read that failed: either
    // must not stand for the rest of the session.
    var reads = 0;
    final container = ProviderContainer(
      retry: neverRetry,
      overrides: [
        serverUiFlagsProvider.overrideWith((ref) async {
          reads++;
          return {'billing_enabled': reads > 1};
        }),
        serverSettingsOverride(const {}),
      ],
    );
    addTearDown(container.dispose);

    var sub = container.listen(billingEnabledProvider, (_, _) {});
    await container.read(serverUiFlagsProvider.future);
    expect(sub.read(), isFalse);
    sub.close();
    await Future<void>.delayed(Duration.zero);

    sub = container.listen(billingEnabledProvider, (_, _) {});
    await container.read(serverUiFlagsProvider.future);
    expect(sub.read(), isTrue);
    expect(reads, 2);
  });

  const alice = CostCenter(id: 1, name: 'Alice', isPrivate: true);
  const workshop = CostCenter(
    id: 2,
    name: 'Workshop',
    budget: CostCenterBudget.monthly,
    budgetLimit: 100,
    budgetAvailable: 62.5,
  );

  /// The form with billing on and [centers] standing for what
  /// `/finance/cost-centers/mine` answers: a list, null for a session the
  /// server refuses to list for, or a throw for a read that failed.
  Future<void> pump(
    WidgetTester tester, {
    QueueItem? item,
    FutureOr<List<CostCenter>?> Function()? centers,
    bool billing = true,
  }) async {
    // Tall enough that the whole form is built: the section sits below the fold.
    usePhoneWindow(tester, dp: 2400);
    await tester.pumpWidget(
      queueFormScreen(
        item ?? archiveDraft(),
        mode: item == null ? QueueEditMode.create : QueueEditMode.edit,
        extra: [
          serverUiFlagsProvider.overrideWith(
            (ref) async => {'billing_enabled': billing},
          ),
          printableCostCentersProvider.overrideWith(
            (ref) async => billing ? await (centers ?? () => [alice])() : [],
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
  }

  QueueItem queued({int? costCenter}) => QueueItem.fromJson({
    'id': 5,
    'position': 1,
    'status': 'pending',
    'printer_id': 1,
    'archive_id': 77,
    'cost_center_id': costCenter,
  });

  Future<void> pick(WidgetTester tester, String name) async {
    await tester.ensureVisible(_costCenterField);
    await tester.tap(_costCenterField);
    await tester.pumpAndSettle();
    await tester.tap(find.text(name).last);
    await tester.pumpAndSettle();
  }

  group('the picker', () {
    testWidgets('offers the centers, the user\'s own first, and sends it', (
      tester,
    ) async {
      await pump(tester, centers: () => [alice, workshop]);

      expect(_costCenterField, findsOneWidget);
      expect(find.text(pl.queueCostCenterPersonal('Alice')), findsOneWidget);

      await submitQueueForm(tester);

      expect(capturedBody?['cost_center_id'], 1);
    });

    testWidgets('sends the one picked instead', (tester) async {
      await pump(tester, centers: () => [alice, workshop]);

      await pick(tester, 'Workshop');
      await submitQueueForm(tester);

      expect(capturedBody?['cost_center_id'], 2);
    });

    testWidgets('falls back to the first when none is the user\'s own', (
      tester,
    ) async {
      await pump(tester, centers: () => [workshop]);

      await submitQueueForm(tester);

      expect(capturedBody?['cost_center_id'], 2);
    });

    testWidgets('says a center without a budget is unlimited', (tester) async {
      await pump(tester, centers: () => [alice, workshop]);
      expect(find.text(pl.queueCostCenterUnlimited), findsOneWidget);

      await pick(tester, 'Workshop');

      expect(find.text(pl.queueCostCenterUnlimited), findsNothing);
    });

    testWidgets('is absent, and sends nothing, without billing', (
      tester,
    ) async {
      await pump(tester, billing: false);

      expect(_costCenterField, findsNothing);
      expect(find.text(pl.queueCostCenterTitle), findsNothing);

      await submitQueueForm(tester);

      expect(capturedBody?.containsKey('cost_center_id'), isFalse);
    });

    testWidgets('keeps the item\'s own center on an edit', (tester) async {
      await pump(
        tester,
        item: queued(costCenter: 2),
        centers: () => [alice, workshop],
      );

      expect(find.text('Workshop'), findsOneWidget);

      await submitQueueForm(tester, edit: true);

      expect(capturedBody?['cost_center_id'], 2);
    });

    testWidgets('gives an item queued before billing one on its edit', (
      tester,
    ) async {
      await pump(tester, item: queued(), centers: () => [alice, workshop]);

      await pick(tester, 'Workshop');
      await submitQueueForm(tester, edit: true);

      expect(capturedBody?['cost_center_id'], 2);
    });
  });

  group('the cost preview', () {
    const tight = CostCenter(
      id: 2,
      name: 'Tight',
      budget: CostCenterBudget.total,
      budgetLimit: 5,
      budgetAvailable: 4,
    );

    Future<void> open(
      WidgetTester tester, {
      required JobCost? cost,
      List<CostCenter> centers = const [tight],
      QueueItem? draft,
      bool billingOn = true,
    }) async {
      usePhoneWindow(tester, dp: 2400);
      await tester.pumpWidget(
        queueFormScreen(
          draft ?? archiveDraft(),
          extra: [
            serverUiFlagsProvider.overrideWith(
              (ref) async => {'billing_enabled': billingOn},
            ),
            printableCostCentersProvider.overrideWith((ref) async => centers),
            jobCostProvider.overrideWith((ref, key) async => cost),
            batchListingProvider.overrideWithValue(const AsyncData(true)),
            serverSettingsOverride(const {'currency': 'USD'}),
          ],
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('says what the job is expected to cost', (tester) async {
      await open(tester, cost: (total: 3.5, anyPrice: true));

      expect(find.text(pl.queueEstimatedCost(r'$3.50')), findsOneWidget);
      expect(find.text(pl.queueInsufficientBudget), findsNothing);
    });

    testWidgets('says it without billing too, as the web does', (tester) async {
      await open(tester, cost: (total: 3.5, anyPrice: true), billingOn: false);

      expect(find.text(pl.queueEstimatedCost(r'$3.50')), findsOneWidget);
      expect(find.text(pl.queueInsufficientBudget), findsNothing);
    });

    testWidgets('says N/A where nothing has a price, as the web does', (
      tester,
    ) async {
      await open(tester, cost: (total: 0, anyPrice: false), billingOn: false);

      expect(
        find.text(pl.queueEstimatedCost(pl.queueCostNotAvailable)),
        findsOneWidget,
      );
    });

    testWidgets('and what several copies cost together', (tester) async {
      await open(tester, cost: (total: 1, anyPrice: true));
      await tester.ensureVisible(byLogId('queue_edit.copies_up'));
      await tester.tap(byLogId('queue_edit.copies_up'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining(pl.queueEstimatedCostForCopies(r'$2.00')),
        findsOneWidget,
        reason: 'two copies at one dollar',
      );
    });

    testWidgets('warns when the job costs more than the center has left', (
      tester,
    ) async {
      await open(tester, cost: (total: 4.5, anyPrice: true));

      expect(find.text(pl.queueInsufficientBudget), findsOneWidget);
    });

    testWidgets('judges all the copies against the budget, not one', (
      tester,
    ) async {
      // 1.5 fits the 4 left; three of them, 4.5, do not.
      await open(tester, cost: (total: 1.5, anyPrice: true));
      expect(find.text(pl.queueInsufficientBudget), findsNothing);

      for (var i = 0; i < 2; i++) {
        await tester.ensureVisible(byLogId('queue_edit.copies_up'));
        await tester.tap(byLogId('queue_edit.copies_up'));
        await tester.pumpAndSettle();
      }

      expect(find.text(pl.queueInsufficientBudget), findsOneWidget);
    });

    testWidgets('a job for any printer of a model has no mapping to price', (
      tester,
    ) async {
      await open(tester, cost: (total: 3.5, anyPrice: true));
      expect(find.text(pl.queueEstimatedCost(r'$3.50')), findsOneWidget);

      await tester.ensureVisible(find.text(pl.queueEditAnyModel('X2D')));
      await tester.tap(find.text(pl.queueEditAnyModel('X2D')));
      await tester.pumpAndSettle();

      expect(find.text(pl.queueEstimatedCost(r'$3.50')), findsNothing);
    });

    testWidgets('a job that exactly fits is not warned about', (tester) async {
      await open(tester, cost: (total: 4, anyPrice: true));

      expect(find.text(pl.queueInsufficientBudget), findsNothing);
    });

    testWidgets('a center with no budget cannot run out', (tester) async {
      await open(
        tester,
        cost: (total: 9999, anyPrice: true),
        centers: const [CostCenter(id: 1, name: 'Alice', isPrivate: true)],
      );

      expect(find.text(pl.queueInsufficientBudget), findsNothing);
    });

    testWidgets('a job nothing prices reads as not available', (tester) async {
      await open(tester, cost: (total: 0, anyPrice: false));

      expect(
        find.text(pl.queueEstimatedCost(pl.queueCostNotAvailable)),
        findsOneWidget,
      );
    });

    testWidgets('nothing to price against shows no line', (tester) async {
      await open(tester, cost: null);

      expect(find.textContaining('\$'), findsNothing);
      expect(find.text(pl.queueInsufficientBudget), findsNothing);
    });
  });

  group('when there is nothing to pick', () {
    testWidgets('a session the server will not list for is told so', (
      tester,
    ) async {
      await pump(tester, centers: () => null);

      expect(find.text(pl.queueBillingCostCentersRefused), findsOneWidget);
      expect(_costCenterField, findsNothing);
      expect(buttonAt(tester, 'queue_create.save').onPressed, isNull);
    });

    testWidgets('a user with no printable center is told to ask', (
      tester,
    ) async {
      await pump(tester, centers: () => const []);

      expect(find.text(pl.queueBillingNoCostCenter), findsOneWidget);
      expect(buttonAt(tester, 'queue_create.save').onPressed, isNull);
    });

    testWidgets('an item that has a center still saves, without resending it', (
      tester,
    ) async {
      await pump(tester, item: queued(costCenter: 3), centers: () => null);

      expect(find.text(pl.queueBillingCostCentersRefused), findsNothing);
      expect(buttonAt(tester, 'queue_edit.save').onPressed, isNotNull);

      await submitQueueForm(tester, edit: true);

      expect(capturedBody?.containsKey('cost_center_id'), isFalse);
    });

    testWidgets('an item with none cannot be saved', (tester) async {
      await pump(tester, item: queued(), centers: () => null);

      expect(find.text(pl.queueBillingCostCentersRefused), findsOneWidget);
      expect(buttonAt(tester, 'queue_edit.save').onPressed, isNull);
    });

    testWidgets('a failed read offers to try again', (tester) async {
      var reads = 0;
      await pump(
        tester,
        centers: () {
          if (reads++ == 0) throw StateError('connection lost');
          return [alice];
        },
      );

      expect(find.text(pl.queueCostCenterLoadFailed), findsOneWidget);
      expect(buttonAt(tester, 'queue_create.save').onPressed, isNull);

      await tester.tap(byLogId('queue_edit.cost_center_retry'));
      await tester.pumpAndSettle();

      expect(_costCenterField, findsOneWidget);
      expect(buttonAt(tester, 'queue_create.save').onPressed, isNotNull);
    });
  });

  testWidgets('Save waits for the list, without flashing a note', (
    tester,
  ) async {
    final list = Completer<List<CostCenter>?>();
    await tester.pumpWidget(
      queueFormScreen(
        archiveDraft(),
        extra: [
          serverUiFlagsProvider.overrideWith(
            (ref) async => {'billing_enabled': true},
          ),
          printableCostCentersProvider.overrideWith((ref) => list.future),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(buttonAt(tester, 'queue_create.save').onPressed, isNull);
    expect(find.text(pl.queueBillingNoCostCenter), findsNothing);
    expect(find.text(pl.queueBillingCostCentersRefused), findsNothing);

    list.complete([alice]);
    await tester.pumpAndSettle();
    expect(buttonAt(tester, 'queue_create.save').onPressed, isNotNull);
  });

  testWidgets('a server without UI flags waits for its settings', (
    tester,
  ) async {
    // Before 1.2.6 the flags answer at once with nothing, and billing is the
    // settings' to say: Save must not be offered in the gap.
    usePhoneWindow(tester, dp: 2400);
    final settings = Completer<Map<String, dynamic>>();
    await tester.pumpWidget(
      queueFormScreen(
        archiveDraft(),
        extra: [
          serverUiFlagsProvider.overrideWith((ref) async => const {}),
          serverSettingsProvider.overrideWith(() => _HeldSettings(settings)),
          printableCostCentersProvider.overrideWith((ref) async => [alice]),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(buttonAt(tester, 'queue_create.save').onPressed, isNull);

    settings.complete({'billing_enabled': true});
    await tester.pumpAndSettle();

    expect(_costCenterField, findsOneWidget);
    expect(buttonAt(tester, 'queue_create.save').onPressed, isNotNull);
  });

  testWidgets('submit waits for the flag, without flashing the note', (
    tester,
  ) async {
    final flags = Completer<Map<String, dynamic>>();
    await tester.pumpWidget(
      queueFormScreen(
        archiveDraft(),
        extra: [serverUiFlagsProvider.overrideWith((ref) => flags.future)],
      ),
    );
    await tester.pump();

    expect(buttonAt(tester, 'queue_create.save').onPressed, isNull);
    expect(find.text(pl.queueBillingNoCostCenter), findsNothing);
    expect(find.text(pl.queueBillingCostCentersRefused), findsNothing);

    flags.complete({'billing_enabled': false});
    await tester.pumpAndSettle();
    expect(buttonAt(tester, 'queue_create.save').onPressed, isNotNull);
  });

  testWidgets('a job with a cost center does not wait for the flag', (
    tester,
  ) async {
    await tester.pumpWidget(
      queueFormScreen(
        queued(costCenter: 3),
        mode: QueueEditMode.edit,
        extra: [
          serverUiFlagsProvider.overrideWith(
            (ref) => Completer<Map<String, dynamic>>().future,
          ),
        ],
      ),
    );
    await tester.pump();

    expect(buttonAt(tester, 'queue_edit.save').onPressed, isNotNull);
  });

  test('an action outside a build waits for the answer', () async {
    Future<bool> settled(
      Map<String, dynamic> flags,
      Map<String, dynamic> settings,
    ) {
      final container = ProviderContainer(
        retry: neverRetry,
        overrides: [
          serverUiFlagsProvider.overrideWith((ref) async => flags),
          serverSettingsOverride(settings),
        ],
      );
      addTearDown(container.dispose);
      return settledBillingEnabled(container);
    }

    expect(await settled({'billing_enabled': true}, const {}), isTrue);
    expect(await settled(const {}, {'billing_enabled': true}), isTrue);
    expect(await settled({'billing_enabled': false}, const {}), isFalse);
  });
}

/// `/settings` held until the test lets it answer.
class _HeldSettings extends ServerSettingsNotifier {
  _HeldSettings(this._answer);

  final Completer<Map<String, dynamic>> _answer;

  @override
  Future<Map<String, dynamic>> build() => _answer.future;

  @override
  Future<void> refresh() async {}
}
