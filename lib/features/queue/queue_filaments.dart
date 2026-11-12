import '../../core/ams/filament_mapping.dart';
import '../../core/ams/slot_addressing.dart';
import '../../core/models/plate_list.dart';
import '../../core/models/printer_status.dart';
import '../../core/models/queue_item.dart';

/// One filament a queued job uses, as its row shows it (`QueueFilamentDisplay`
/// in `QueuePage.tsx`). [slotLabel] names the tray the stored mapping sends it
/// to, when the live status describes that tray; [emptySlot] says the printer
/// reports that tray empty, which the scheduler would dispatch to as stored.
typedef QueueFilament = ({
  int slotId,
  String type,
  String color,
  String? colorName,
  String? slotLabel,
  bool emptySlot,
});

/// `resolveQueueFilaments`: the plate's slots, each with its queue override,
/// and where the stored mapping names a tray, that tray's live filament.
///
/// The plate metadata decides which slots the job uses; before it arrives (or
/// with none) the queue overrides, then the item's own filament colour. While
/// the job prints, a slot whose spool ran out shows the backup the printer
/// switched to ([backupTrays]).
List<QueueFilament> resolveQueueFilaments(
  QueueItem item,
  List<PlateInfo> plates,
  List<LoadedFilament> loaded,
  PrinterStatus? status,
) {
  final backups = item.status == 'printing'
      ? backupTrays(item.amsMapping, status?.trayChangeLog)
      : const <int, int>{};
  QueueFilament resolveSlot(QueueFilament planned) {
    final slotId = planned.slotId;
    final mapping = item.amsMapping;
    final stored = slotId > 0 && mapping != null && slotId <= mapping.length
        ? mapping[slotId - 1]
        : null;
    if (stored == null || stored < 0) return planned;
    final tray = backups[stored] ?? stored;
    final live = loaded.where((f) => f.globalTrayId == tray).firstOrNull;
    if (live != null) {
      return (
        slotId: slotId,
        type: live.type,
        color: live.color,
        colorName: null,
        slotLabel: mappingSlotLabel(live, status),
        emptySlot: false,
      );
    }
    final empty = emptyMappedSlotLabel(status, tray);
    if (empty == null) return planned;
    return (
      slotId: slotId,
      type: planned.type,
      color: planned.color,
      colorName: planned.colorName,
      slotLabel: empty,
      emptySlot: true,
    );
  }

  QueueFilament planned(int slotId, String type, String color, String? name) =>
      (
        slotId: slotId,
        type: type,
        color: color,
        colorName: name,
        slotLabel: null,
        emptySlot: false,
      );

  final plate = item.plateId != null
      ? plates.where((p) => p.index == item.plateId).firstOrNull
      : plates.firstOrNull;
  final overrides = {
    for (final o in item.filamentOverrides ?? const <Map<String, dynamic>>[])
      if (o['slot_id'] is int) o['slot_id'] as int: o,
  };
  String? text(Object? v) => v is String && v.trim().isNotEmpty ? v : null;

  if (plate != null) {
    return [
      for (final f in plate.filaments)
        if (f.usedInPlate && f.usedGrams > 0)
          resolveSlot(
            planned(
              f.slotId,
              text(overrides[f.slotId]?['type']) ?? f.type,
              text(overrides[f.slotId]?['color']) ?? f.color,
              text(overrides[f.slotId]?['color_name']),
            ),
          ),
    ];
  }
  if (overrides.isNotEmpty) {
    return [
      for (final o in overrides.values)
        resolveSlot(
          planned(
            o['slot_id'] as int,
            text(o['type']) ?? '',
            text(o['color']) ?? '',
            text(o['color_name']),
          ),
        ),
    ];
  }
  final colour = item.filamentColor;
  if (colour != null && colour.isNotEmpty) {
    return [resolveSlot(planned(1, item.filamentType ?? '', colour, null))];
  }
  return const [];
}

/// `backupTrays`: the backup tray each mapped tray handed over to during the
/// running print. With AMS Filament Backup on, a spool that runs out is
/// replaced by an identical one in another slot while the stored mapping still
/// names the empty one. The log shows the switch: a tray the mapping does not
/// name, right after the tray it took over from. A backup that runs out in turn
/// hands over again, so the chain resolves to the slot the mapping named.
Map<int, int> backupTrays(List<int>? mapping, List<(int, int)>? log) {
  final backups = <int, int>{};
  if (mapping == null || mapping.isEmpty || log == null || log.isEmpty) {
    return backups;
  }
  final mapped = {
    for (final t in mapping)
      if (t >= 0) t,
  };
  // Backup tray -> the mapped tray it stands in for.
  final standsInFor = <int, int>{};
  int? previous;
  for (final (tray, _) in log) {
    if (previous != null &&
        !mapped.contains(tray) &&
        !standsInFor.containsKey(tray)) {
      final original = mapped.contains(previous)
          ? previous
          : standsInFor[previous];
      if (original != null) {
        standsInFor[tray] = original;
        backups[original] = tray;
      }
    }
    previous = tray;
  }
  return backups;
}

/// `emptyMappedSlotLabel`: the label of mapped tray [global] when the printer
/// positively reports it empty, else null — offline, a unit gone, an external
/// input (it sends no presence signal), or a spool nobody named, which a
/// non-RFID spool also looks like (#2527).
String? emptyMappedSlotLabel(PrinterStatus? status, int global) {
  if (status == null || status.connected != true) return null;
  final layout = status.trayLayout;
  if (isExternalTray(global, rack: layout.rack)) return null;
  final located = layout.locate(global);
  if (located == null) return null;
  final (:amsId, :trayId) = located;
  final ht = isAmsHtId(amsId);
  final unit = status.ams?.where((u) => u.id == amsId).firstOrNull;
  final trays = unit?.trays ?? const <AmsTray>[];
  final tray = ht
      ? trays.firstOrNull
      : trays.where((t) => t.id == trayId).firstOrNull;
  if (tray?.emptyKind != EmptySlotKind.empty) return null;
  return formatSlotLabel(
    amsId,
    trayId,
    isHt: ht,
    amsType: layout.amsTypeOf(amsId),
  );
}
