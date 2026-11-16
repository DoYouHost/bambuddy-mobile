import '../../core/models/inventory.dart';

/// Where the low-filament alert reads from.
enum LowStockSource {
  /// The AMS `remain` of each tray against this phone's own threshold: what the
  /// app did before it read the inventory, and what a session or a server that
  /// cannot read the inventory still gets.
  phone,

  /// The service has asked the inventory and not been answered yet. Neither
  /// rule speaks meanwhile, so a start-up does not alert twice for one slot.
  pending,

  /// The server's rule, from the spool inventory.
  inventory,
}

/// One spool in one AMS slot, as the server addresses it. A different spool in
/// the same slot is a different key, which is what lets a swapped-in spool that
/// is already low alert in its own right.
typedef LowStockKey = ({int printerId, int amsId, int trayId, int spoolId});

class LowStockSlot {
  const LowStockSlot(this.percent, this.threshold);

  final double percent;
  final double threshold;

  /// Strictly below, and back above at `>=`: no margin between the two, as in
  /// the server's `_emit_filament_low` and for the reason it gives (a slot
  /// refilled can alert again, one sitting just under stays quiet).
  bool get isLow => percent < threshold;
}

/// The slots that have a spool and a percentage to judge, from the spool list
/// and the assignments. The server's `_check_filament_low`, internal path:
/// archived spools are not stock, and a spool with no label weight has no
/// percentage, so neither is judged. An assignment whose spool is not in
/// [spools] (archived and not listed, or just deleted) is skipped too.
Map<LowStockKey, LowStockSlot> lowStockSlots({
  required List<Spool> spools,
  required List<SpoolAssignment> assignments,
  required double globalThreshold,
}) {
  final byId = {for (final s in spools) s.id: s};
  final slots = <LowStockKey, LowStockSlot>{};
  for (final a in assignments) {
    final spool = byId[a.spoolId];
    final percent = spool?.remainingPercent;
    if (spool == null || spool.isArchived || percent == null) continue;
    slots[(
      printerId: a.printerId,
      amsId: a.amsId,
      trayId: a.trayId,
      spoolId: spool.id,
    )] = LowStockSlot(
      percent,
      spool.lowStockThresholdFor(globalThreshold),
    );
  }
  return slots;
}

/// What has been said about low spools, and what is owed. The server's
/// `_notified_filament_low` with one difference of the app's own: the first
/// look only records. A service is built on every entry into the background, so
/// a spool that was low when it started has been low for a while, and saying
/// so each time the app is left would be noise (docs/notification-rules.md,
/// "Baseline: the first frame fires nothing").
class LowStockLatch {
  final Set<LowStockKey> _said = {};
  bool _seen = false;

  /// The keys that crossed below their threshold since the last look and are
  /// not yet said, and marks them said. [onlyIf] can hold one back unmarked
  /// (a printer with no frame yet has nothing to name it by), so a later look
  /// still owes it.
  ///
  /// A key absent from [slots] keeps what was said about it, as on the server: a
  /// spool list that briefly came back empty must not re-alert every spool when
  /// it recovers. Only a reading back at or above the threshold clears one.
  List<LowStockKey> look(
    Map<LowStockKey, LowStockSlot> slots, {
    bool Function(LowStockKey key)? onlyIf,
  }) {
    final first = !_seen;
    _seen = true;
    final crossed = <LowStockKey>[];
    for (final MapEntry(:key, :value) in slots.entries) {
      if (!value.isLow) {
        _said.remove(key);
      } else if (!_said.contains(key)) {
        if (first) {
          _said.add(key);
        } else if (onlyIf?.call(key) ?? true) {
          _said.add(key);
          crossed.add(key);
        }
      }
    }
    return crossed;
  }

  /// A printer that is gone takes what was said about its slots with it.
  void forget(Set<int> printerIds) =>
      _said.removeWhere((key) => printerIds.contains(key.printerId));

  int get said => _said.length;
}
