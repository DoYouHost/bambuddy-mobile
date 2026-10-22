import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/action_failure.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/models/plate_list.dart';
import '../../data/queue_repository.dart';
import '../../providers.dart';
import '../common/dash_async.dart';
import '../orders/orders_providers.dart';
import '../slicer/slice_providers.dart';

/// What [createQueueJobs] did besides adding the copies.
class QueueCreateOutcome {
  const QueueCreateOutcome({required this.orderRefused});

  /// The order for the copies was refused and they went in as a plain batch:
  /// the caller promised an order, so its message has to say it was not one.
  final bool orderRefused;
}

/// Creates the queue item for a new print job — one copy or several — with
/// everything that has to be settled around the `POST /queue/` itself: the
/// order for two or more copies, the outcome flag against the server's default,
/// and the clean-up of an order whose copies were refused.
///
/// Shared by the print form and the controller's print screen, so the two can
/// not drift apart on rules that cite web-parity bugs. [buildOptions] resolves
/// everything that needs the caller's own state; it runs **after** the order is
/// made and the outcome flag is settled, as the form's code always did, so it
/// samples providers as late as before. This function fills in the three
/// fields only known here (see [QueueCreateOptions.withOrder]).
///
/// [plateId] is the plate the user picked; an order makes the item carry the
/// plate its target names instead. It is the only plate input: the built
/// options must leave `plateId` null. [confirmOutcomeChoice] is the user's own
/// toggle (null until touched) and [confirmOutcomeSticky] a reprint of an
/// archive that already asks, which stays on whatever the switch says.
Future<QueueCreateOutcome> createQueueJobs({
  required QueueRepository repo,
  required ProviderContainer providers,
  required int? archiveId,
  required int? libraryFileId,
  required String sourceName,
  required int? printerId,
  required int copies,
  required bool insertAtTop,
  required int? plateId,
  required bool? confirmOutcomeChoice,
  required bool confirmOutcomeSticky,
  required QueueCreateOptions Function() buildOptions,
}) async {
  final order = await _createOrder(
    providers,
    archiveId: archiveId,
    libraryFileId: libraryFileId,
    sourceName: sourceName,
    copies: copies,
    plateId: plateId,
  );
  final confirmOutcome = await _confirmOutcomeForCreate(
    providers,
    choice: confirmOutcomeChoice,
    sticky: confirmOutcomeSticky,
  );
  final options = buildOptions();
  assert(
    options.plateId == null,
    'plateId is a parameter of createQueueJobs; the options must not set it',
  );
  final full = options.withOrder(
    // Into an order, the item carries the plate its target names.
    plateId: order.id == null ? plateId : order.plate.id,
    batchId: order.id,
    confirmOutcome: confirmOutcome,
  );
  // ASAP is a position at insertion, not a stored field — the web sends it the
  // same way, and it is what makes "reprint" print next.
  try {
    await (archiveId != null
        ? repo.addFromArchive(
            archiveId,
            printerId: printerId,
            quantity: copies,
            insertAtTop: insertAtTop,
            options: full,
          )
        : repo.addFromLibraryFile(
            libraryFileId!,
            printerId: printerId,
            quantity: copies,
            insertAtTop: insertAtTop,
            options: full,
          ));
  } on Object catch (e) {
    // An order with targets and no runs is listed, owes every copy and has
    // nothing to clone them from. Ungrouping an empty one deletes it — but
    // only after a refusal: a timeout may have queued the copies, and
    // ungrouping would then unlink live runs while the user queues again.
    if (order.id != null && _isRefusal(e)) {
      try {
        await providers.read(batchRepositoryProvider).ungroup(order.id!);
      } on AppApiException {
        // The create's own error is the one the user has to see.
      }
    }
    rethrow;
  }
  return QueueCreateOutcome(orderRefused: order.refused);
}

/// Whether the server answered and refused — nothing was written. A 5xx
/// is not one: a proxy's 502/504 can arrive after the server committed,
/// exactly like a dropped connection.
bool _isRefusal(Object e) =>
    e is AuthException || (e is ApiException && (e.statusCode ?? 500) < 500);

typedef _Plate = ({int? id, String? name});

/// The order for the copies, made first — the web's print dialog does the same.
/// No order for one copy, on a server without orders, and when the order is
/// refused: the copies then go in as a plain grouping, which is what
/// `quantity` alone makes, so the print is not lost over its tracking.
///
/// Only a refusal falls back; see [_isRefusal] for what is not one.
Future<({int? id, _Plate plate, bool refused})> _createOrder(
  ProviderContainer providers, {
  required int? archiveId,
  required int? libraryFileId,
  required String sourceName,
  required int copies,
  required int? plateId,
}) async {
  if (copies < 2) {
    return (id: null, plate: (id: plateId, name: null), refused: false);
  }
  final supported = await settledGate(
    providers,
    batchOrdersProvider,
  ).catchError((Object _) => false);
  if (!supported) {
    return (id: null, plate: (id: plateId, name: null), refused: false);
  }
  final plate = await _orderPlate(
    providers,
    archiveId: archiveId,
    libraryFileId: libraryFileId,
    plateId: plateId,
  );
  try {
    final order = await providers
        .read(batchRepositoryProvider)
        .create(
          name: '${_baseName(sourceName)} ×$copies',
          archiveId: archiveId,
          libraryFileId: archiveId == null ? libraryFileId : null,
          // The runs are matched to the target by plate, so the target
          // names the plate the item will carry — null for a whole file.
          plates: [
            (plateId: plate.id, plateName: plate.name, quantity: copies),
          ],
        );
    return (id: order.id, plate: plate, refused: false);
  } on AppApiException catch (e) {
    // No answer, or a 5xx: the order may exist, and a grouping queued
    // beside it would leave it owing every copy. The submit stops.
    if (!_isRefusal(e)) rethrow;
    // Shown, as the outcome of the whole submit.
    recordActionFailure(e, action: 'queue_create.order', shown: true);
    return (id: null, plate: plate, refused: true);
  }
}

/// The plate an order's target names. A multi-plate file with no plate
/// picked prints plate 1 (`plate_id or 1` server-side) and the form says
/// so; a null target would read "whole file" on the orders screen instead.
///
/// Awaited, not read: a submit before the plate list has loaded would
/// otherwise take a multi-plate file for a single-plate one.
Future<_Plate> _orderPlate(
  ProviderContainer providers, {
  required int? archiveId,
  required int? libraryFileId,
  required int? plateId,
}) async {
  final source = archiveId != null
      ? (true, archiveId)
      : (libraryFileId != null ? (false, libraryFileId) : null);
  final plates = source == null
      ? PlateList.none
      : await providers
            .read(plateListProvider(source).future)
            .catchError((Object _) => PlateList.none);
  if (!plates.isMultiPlate) return (id: plateId, name: null);
  final id = plateId ?? 1;
  return (id: id, name: plates.byIndex(id)?.name);
}

/// The flag for a new job, or null to leave the key out where the server
/// would drop it. `POST /queue/` does not read the server's default itself
/// (only the paths without a dialog do), so an untouched switch sends the
/// default — waited for, since a job submitted before it arrived would
/// otherwise go out as `false`.
///
/// A choice the user made stands unless the gate has since settled on no:
/// it was made on a switch that was on screen, and a gate briefly reloading
/// must not throw it away.
Future<bool?> _confirmOutcomeForCreate(
  ProviderContainer providers, {
  required bool? choice,
  required bool sticky,
}) async {
  final gate = providers.read(queueOutcomeProvider);
  if (gate.valueOrNull == false) return null;
  if (choice != null) return choice;
  if (sticky) return true;
  if (!gate.orFalse) return null;
  return settledGate(
    providers,
    defaultConfirmOutcomeProvider,
  ).catchError((Object _) => false);
}

/// A file name as the server names a batch after it (`print_queue.py`).
String _baseName(String name) =>
    name.replaceAll('.gcode.3mf', '').replaceAll('.3mf', '');
