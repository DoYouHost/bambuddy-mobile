import 'package:bambuddy_mobile/core/models/cost_center.dart';
import 'package:bambuddy_mobile/features/queue/queue_cost_center_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const alice = CostCenter(id: 1, name: 'Alice', isPrivate: true);
  const workshop = CostCenter(id: 2, name: 'Workshop', budgetAvailable: 5);

  group('which steps let a job through', () {
    test('only billing off and a centre to pick', () {
      expect(costCenterAllowsCreate(CostCenterStep.off), isTrue);
      expect(costCenterAllowsCreate(CostCenterStep.pick), isTrue);
      for (final step in [
        CostCenterStep.unknown,
        CostCenterStep.loading,
        CostCenterStep.none,
        CostCenterStep.refused,
        CostCenterStep.failed,
      ]) {
        expect(costCenterAllowsCreate(step), isFalse, reason: '$step');
      }
    });
  });

  group('the centre a job is booked to', () {
    test('what was picked, while it is still on offer', () {
      expect(selectedCostCenter([alice, workshop], 2), workshop);
    });

    test('the web default when nothing was picked', () {
      expect(selectedCostCenter([workshop, alice], null), alice);
    });

    test('the web default when the pick is no longer on offer', () {
      expect(selectedCostCenter([alice], 2), alice);
    });

    test('nothing when there is nothing to choose from', () {
      expect(selectedCostCenter(const [], 2), isNull);
    });
  });

  group('the budget warning', () {
    test('all the copies together are weighed against what is left', () {
      const cost = (total: 2.0, anyPrice: true);
      expect(jobExceedsBudget(cost, workshop, 2), isFalse, reason: '4 of 5');
      expect(jobExceedsBudget(cost, workshop, 3), isTrue, reason: '6 of 5');
    });

    test('exactly what is left still fits', () {
      expect(
        jobExceedsBudget((total: 5.0, anyPrice: true), workshop, 1),
        isFalse,
      );
    });

    test('says nothing without a cost or a figure for the centre', () {
      expect(jobExceedsBudget(null, workshop, 1), isFalse);
      expect(
        jobExceedsBudget((total: 99.0, anyPrice: true), alice, 1),
        isFalse,
      );
      expect(jobExceedsBudget((total: 99.0, anyPrice: true), null, 1), isFalse);
    });
  });
}
