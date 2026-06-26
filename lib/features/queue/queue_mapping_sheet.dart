import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/models/filament_requirement.dart';
import '../../core/models/inventory.dart';
import '../../core/models/printer_status.dart';
import '../../core/models/queue_item.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../slicer/slice_providers.dart';

/// One AMS slot (or external spool) a file filament can be mapped to.
typedef _Tray = ({int global, String? type, String? color, int? remain, bool external});

/// Loaded filaments for a printer's AMS, sourced from inventory assignments so
/// it works even when the printer is OFFLINE (assignments persist server-side).
/// Falls back to the live printer status if no assignments exist.
final printerTraysProvider =
    FutureProvider.autoDispose.family<List<_Tray>, int>((ref, printerId) async {
  final inv = ref.watch(inventoryRepositoryProvider);
  var assignments = const <SpoolAssignment>[];
  var spools = const <Spool>[];
  try {
    assignments = await inv.fetchAssignments();
    spools = await inv.fetchSpools();
  } on AppApiException {
    // Ignore — fall through to live status.
  }
  final byId = {for (final s in spools) s.id: s};
  final out = <_Tray>[];
  for (final a in assignments) {
    if (a.printerId != printerId) continue;
    final s = byId[a.spoolId];
    // AMS global index = unit*4 + slot; external spools use 254/255.
    final global = a.isExternalSpool ? 254 + a.trayId : a.amsId * 4 + a.trayId;
    out.add((
      global: global,
      type: s?.material,
      color: s?.rgba,
      remain: null,
      external: a.isExternalSpool,
    ));
  }
  if (out.isNotEmpty) return out;
  // Fallback: whatever the printer reports live (only when online).
  try {
    return _traysFromStatus(
        await ref.watch(printersRepositoryProvider).fetchStatus(printerId));
  } on AppApiException {
    return const [];
  }
});

List<_Tray> _traysFromStatus(PrinterStatus? status) {
  if (status == null) return const [];
  final out = <_Tray>[];
  final units = status.ams ?? const <AmsUnit>[];
  for (var u = 0; u < units.length; u++) {
    for (final t in units[u].trays ?? const <AmsTray>[]) {
      if (t.isEmpty) continue;
      final int global = u * 4 + (t.id ?? 0);
      out.add((
        global: global,
        type: t.trayType,
        color: t.trayColor,
        remain: t.remain,
        external: false,
      ));
    }
  }
  for (final e in status.externalSpools) {
    if (e.isEmpty) continue;
    final int global = e.id ?? 254;
    out.add((
      global: global,
      type: e.trayType,
      color: e.trayColor,
      remain: e.remain,
      external: true,
    ));
  }
  return out;
}

/// Opens the filament-mapping screen for [item] against [printerId]. Pre-fills
/// auto-matched defaults; the user may adjust, leave slots on "auto", or just
/// confirm. Returns the `ams_mapping` array (`-1` = auto for unset slots), or
/// null if dismissed. Persisting/starting is the caller's job — [confirmLabel]
/// is the action verb on the button (e.g. "Start" or "Save").
Future<List<int>?> showQueueMappingSheet(
  BuildContext context, {
  required QueueItem item,
  required int printerId,
  required String confirmLabel,
}) {
  return showModalBottomSheet<List<int>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _MappingSheet(
        item: item, printerId: printerId, confirmLabel: confirmLabel),
  );
}

class _MappingSheet extends ConsumerStatefulWidget {
  const _MappingSheet({
    required this.item,
    required this.printerId,
    required this.confirmLabel,
  });
  final QueueItem item;
  final int printerId;
  final String confirmLabel;

  @override
  ConsumerState<_MappingSheet> createState() => _MappingSheetState();
}

class _MappingSheetState extends ConsumerState<_MappingSheet> {
  // Selected global AMS tray per filament slot (null = auto / -1).
  List<int?> _selected = [];

  AppLocalizations get _l10n => AppLocalizations.of(context);
  bool get _isArchive => widget.item.archiveId != null;
  int? get _sourceId => widget.item.archiveId ?? widget.item.libraryFileId;

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n;
    final theme = Theme.of(context);
    final sourceId = _sourceId;

    Widget wrap(Widget child) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
            child: child,
          ),
        );

    if (sourceId == null) {
      return wrap(Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(l10n.mappingNoSlots),
      ));
    }

    final reqsAsync =
        ref.watch(filamentRequirementsProvider((_isArchive, sourceId)));
    final traysAsync = ref.watch(printerTraysProvider(widget.printerId));

    return wrap(
      reqsAsync.isLoading || traysAsync.isLoading
          ? const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()))
          : _content(theme, reqsAsync.valueOrNull ?? const [],
              traysAsync.valueOrNull ?? const []),
    );
  }

  Widget _content(
      ThemeData theme, List<FilamentRequirement> reqs, List<_Tray> trays) {
    final l10n = _l10n;
    if (reqs.isEmpty) {
      // No per-slot info — nothing to map; let the caller proceed with defaults.
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(l10n.mappingNoSlots),
            ),
            _confirmButton(const []),
          ],
        ),
      );
    }

    _initSelection(reqs, trays);

    return ListView(
      shrinkWrap: true,
      children: [
        Text(l10n.queueFilamentMapping, style: theme.textTheme.titleLarge),
        const SizedBox(height: 2),
        Text(widget.item.displayName,
            style: theme.textTheme.bodySmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis),
        if (trays.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(l10n.mappingNoAms(widget.item.printerName ?? ''),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
        const SizedBox(height: 12),
        for (var i = 0; i < reqs.length; i++)
          _slotRow(theme, i, reqs[i], trays),
        const SizedBox(height: 16),
        _confirmButton([for (final s in _selected) s ?? -1]),
      ],
    );
  }

  Widget _confirmButton(List<int> mapping) => FilledButton.icon(
        icon: const Icon(Icons.check),
        label: Text(widget.confirmLabel),
        onPressed: () => Navigator.pop(context, mapping),
      );

  Widget _slotRow(
      ThemeData theme, int i, FilamentRequirement req, List<_Tray> trays) {
    final l10n = _l10n;
    final sel = _selected[i];
    final matches = sel == null ? null : trays.where((t) => t.global == sel);
    final selTray = (matches != null && matches.isNotEmpty) ? matches.first : null;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        // Show the chosen filament's colour once mapped, else the file's
        // required colour.
        leading: _swatch(theme, selTray?.color ?? req.color, 28),
        title: Text(l10n.sliceFilamentNumbered('${i + 1}'),
            style: theme.textTheme.labelMedium),
        subtitle: Text(
          selTray == null
              ? l10n.mappingPickTray
              : '${_trayLabel(selTray)} · ${selTray.type ?? ''}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: trays.isEmpty ? null : () => _pickTray(i, trays),
      ),
    );
  }

  Future<void> _pickTray(int slot, List<_Tray> trays) async {
    final theme = Theme.of(context);
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final t in trays)
              ListTile(
                leading: _swatch(theme, t.color, 28),
                title: Text(_trayLabel(t)),
                subtitle: Text([
                  ?t.type,
                  if (t.remain != null && t.remain! >= 0) '${t.remain}%',
                ].join(' · ')),
                trailing: _selected[slot] == t.global
                    ? Icon(Icons.check, color: theme.colorScheme.primary)
                    : null,
                onTap: () => Navigator.pop(ctx, t.global),
              ),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _selected[slot] = picked);
  }

  // --- helpers ---

  /// Seed each slot from the item's existing mapping, else auto-match by
  /// material then closest colour. Runs once (when sizing matches).
  void _initSelection(List<FilamentRequirement> reqs, List<_Tray> trays) {
    if (_selected.length == reqs.length) return;
    final existing = widget.item.amsMapping;
    _selected = List<int?>.generate(reqs.length, (i) {
      if (existing != null && i < existing.length && existing[i] >= 0) {
        final g = existing[i];
        if (trays.any((t) => t.global == g)) return g;
      }
      return _autoMatch(reqs[i], trays);
    });
  }

  int? _autoMatch(FilamentRequirement req, List<_Tray> trays) {
    final ofType = [
      for (final t in trays)
        if (req.type == null ||
            (t.type != null && _typeMatches(t.type!, req.type!)))
          t,
    ]..sort((a, b) => _colorDistance(a.color, req.color)
        .compareTo(_colorDistance(b.color, req.color)));
    if (ofType.isNotEmpty) return ofType.first.global;
    return trays.length == 1 ? trays.first.global : null;
  }

  String _trayLabel(_Tray t) => t.external
      ? _l10n.mappingExternalSpool
      : _l10n.mappingAmsSlot('${t.global ~/ 4 + 1}', '${t.global % 4 + 1}');

  Widget _swatch(ThemeData theme, String? hex, double size) {
    final c = _color(hex);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c ?? theme.colorScheme.surfaceContainerHighest,
        shape: BoxShape.circle,
        border: Border.all(color: theme.dividerColor),
      ),
      child: c == null
          ? Icon(Icons.help_outline,
              size: size * 0.6, color: theme.colorScheme.onSurfaceVariant)
          : null,
    );
  }
}

bool _typeMatches(String a, String b) {
  final x = a.toUpperCase().trim(), y = b.toUpperCase().trim();
  return x == y || x.startsWith(y) || y.startsWith(x);
}

double _colorDistance(String? a, String? b) {
  final ca = _rgb(a), cb = _rgb(b);
  if (ca == null || cb == null) return double.maxFinite;
  final dr = ca.$1 - cb.$1, dg = ca.$2 - cb.$2, db = ca.$3 - cb.$3;
  return (dr * dr + dg * dg + db * db).toDouble();
}

/// Parse the leading `RRGGBB` of `#RRGGBB` or `RRGGBBAA`.
(int, int, int)? _rgb(String? hex) {
  if (hex == null) return null;
  var h = hex.trim();
  if (h.startsWith('#')) h = h.substring(1);
  if (h.length < 6) return null;
  final v = int.tryParse(h.substring(0, 6), radix: 16);
  if (v == null) return null;
  return ((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF);
}

Color? _color(String? hex) {
  final rgb = _rgb(hex);
  if (rgb == null) return null;
  return Color.fromARGB(255, rgb.$1, rgb.$2, rgb.$3);
}
