import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import '../../core/ams/job_cost.dart';
import '../../core/models/cost_center.dart';
import '../../providers.dart';

/// Where a print form stands on billing, which decides what its cost-center
/// section shows and whether it can submit ([docs/billing.md]).
enum CostCenterStep {
  /// Neither the server's UI flags nor, on a server without them, its settings
  /// have said whether billing is on.
  unknown,

  /// Billing is off, so no cost center is asked for or sent.
  off,

  /// Billing is on and the centers are being read.
  loading,

  /// Something to choose from.
  pick,

  /// Billing is on and this user may print to no active center: an administrator
  /// has to grant one.
  none,

  /// Billing is on but this session may not list its centers (an API key on a
  /// server before #3256), which only the browser gets around.
  refused,

  /// The list could not be read — a dropped connection, a server error.
  failed,
}

typedef CostCenterState = ({CostCenterStep step, List<CostCenter> centers});

/// `ref.watch` or `ref.read`, whichever the caller is allowed: a build watches,
/// a submit reads what has already resolved.
typedef ProviderReader = T Function<T>(ProviderListenable<T> provider);

/// What a form can do about billing, from the flag and the centers this session
/// may book to.
CostCenterState costCenterStateOf(ProviderReader read) {
  // A server before 1.2.6 has no UI flags and answers them at once with
  // nothing, so billing is then the full settings' to say.
  final flags = read(serverUiFlagsProvider);
  final flagAnswered = flags.value?.containsKey('billing_enabled') ?? false;
  if (flags.isLoading ||
      (!flagAnswered && read(serverSettingsProvider).isLoading)) {
    return (step: CostCenterStep.unknown, centers: const []);
  }
  if (!read(billingEnabledProvider)) {
    return (step: CostCenterStep.off, centers: const []);
  }
  return read(printableCostCentersProvider).when(
    loading: () => (step: CostCenterStep.loading, centers: const []),
    error: (_, _) => (step: CostCenterStep.failed, centers: const []),
    data: (centers) => switch (centers) {
      null => (step: CostCenterStep.refused, centers: const []),
      [] => (step: CostCenterStep.none, centers: const []),
      _ => (step: CostCenterStep.pick, centers: centers),
    },
  );
}

/// Whether a job that needs a center may be sent: every step that cannot offer
/// a pick leaves it stuck.
bool costCenterAllowsCreate(CostCenterStep step) =>
    step == CostCenterStep.off || step == CostCenterStep.pick;

/// The center a write sends: what the user picked if it is still on offer, else
/// the web's default. Null when there is nothing to choose from.
CostCenter? selectedCostCenter(List<CostCenter> centers, int? pickedId) =>
    centers.where((c) => c.id == pickedId).firstOrNull ??
    defaultCostCenter(centers);

/// Whether the job, all its [copies] together, is more than [selected] has left.
/// The server refuses it when it does not fit; this says so before the form is
/// sent. False while the cost or the center's remaining budget is not known.
bool jobExceedsBudget(JobCost? cost, CostCenter? selected, int copies) {
  final available = selected?.budgetAvailable;
  return cost != null && available != null && cost.total * copies > available;
}
