import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../common/api_failure_snack.dart';
import '../../core/diagnostics/log_tag.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/models/filament_requirement.dart';
import '../../core/models/slice_job.dart';
import '../../core/models/slicer_preset.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import '../../providers.dart';
import '../../core/models/process_option.dart';
import '../../core/slicer/process_settings_codec.dart';
import '../common/dash_search_field.dart';
import '../stats/stats_common.dart' show fmtDuration, colorFromHex;
import 'process_settings_screen.dart';
import 'slice_providers.dart';

/// What gets sliced — an archive or a library file. Both use the same
/// `SliceRequest`; only the enqueue endpoint differs.
class SliceTarget {
  const SliceTarget.archive(this.id, this.name) : isArchive = true;
  const SliceTarget.libraryFile(this.id, this.name) : isArchive = false;

  final int id;
  final String name;
  final bool isArchive;
}

/// Opens the slice modal for [target]. Returns true if a slice completed
/// successfully (so callers can refresh their lists). Caller is responsible for
/// gating on [slicerEnabledProvider] / capabilities before showing.
Future<bool> showSliceSheet(BuildContext context, SliceTarget target) async {
  final done = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _SliceSheet(target: target),
  );
  return done ?? false;
}

class _SliceSheet extends ConsumerStatefulWidget {
  const _SliceSheet({required this.target});
  final SliceTarget target;

  @override
  ConsumerState<_SliceSheet> createState() => _SliceSheetState();
}

/// Canonical BambuStudio / OrcaSlicer bed types accepted by `SliceRequest`'s
/// `bed_type`. `null` ⇒ inherit the process preset's plate unchanged.
const _bedTypes = <String>[
  'Cool Plate',
  'Textured PEI Plate',
  'Smooth PEI Plate',
  'Engineering Plate',
  'High Temp Plate',
  'Cool Plate (SuperTack)',
  'Supertack Plate',
];

class _SliceSheetState extends ConsumerState<_SliceSheet> {
  SlicerPreset? _printer;
  SlicerPreset? _process;
  String? _bedType; // null = inherit from the process preset
  // One entry per filament slot the model needs (>= 1). A multicolor 3MF has
  // several; the slice request maps these to slots in order.
  List<SlicerPreset?> _filaments = [];
  bool _submitting = false;

  /// Let the slicer choose each object's orientation (`--orient 1`). Off by
  /// default, exactly as the server has it: it rotates geometry, so a model the
  /// designer laid flat on purpose would silently change.
  bool _autoOrient = false;

  /// Let the slicer lay the objects out on the plate (`--arrange 1`). Off by
  /// default for the same reason — it discards a deliberate layout.
  bool _autoArrange = false;

  /// Process-option edits from the settings screen, as the user typed them.
  ///
  /// What actually goes on the wire is derived from these rather than stored, so
  /// switching the process preset re-decides which of them are deviations at
  /// all: an edit matching the new preset's own value stops being an override.
  Map<String, Object> _processValues = {};

  AppLocalizations get _l10n => AppLocalizations.of(context);

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n;
    final theme = Theme.of(context);
    final presetsAsync = ref.watch(slicerPresetsProvider);
    final ownedCodes =
        ref.watch(ownedPrinterCodesProvider).valueOrNull ?? const <String>{};
    final owned =
        ref.watch(ownedFilamentsProvider).valueOrNull ?? const <OwnedFilament>[];
    final reqs = ref
            .watch(filamentRequirementsProvider(
                (widget.target.isArchive, widget.target.id)))
            .valueOrNull ??
        const <FilamentRequirement>[];

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: presetsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (err, _) => Padding(
            padding: const EdgeInsets.all(24),
            child: Text(err is AppApiException
                ? err.localized(l10n)
                : l10n.sliceNoPresets),
          ),
          data: (presets) {
            // One filament slot per requirement (at least one).
            final slotCount = reqs.isEmpty ? 1 : reqs.length;
            _resizeFilaments(slotCount);

            final printers = _filterPrinters(presets.printers, ownedCodes);
            _printer ??= _firstLocalOr(printers);
            final code = _printer == null
                ? null
                : _codeOfPrinter(_printer!, ownedCodes);
            final processes = _filterProcesses(presets.processes, code);
            _process ??= _firstLocalOr(processes);

            // One filament list for every slot — any owned, printer-compatible
            // filament is selectable (swap PLA↔PETG↔TPU freely). The model's
            // per-slot type/colour only seeds the auto-picked default; plate
            // compatibility is enforced server-side at slice time.
            final filaments = _filterFilaments(presets.filaments, code, owned);
            for (var i = 0; i < slotCount; i++) {
              _filaments[i] ??= _pickDefaultFilament(
                  filaments, owned, i < reqs.length ? reqs[i] : null);
            }

            final ready = _printer != null &&
                _process != null &&
                _filaments.every((f) => f != null) &&
                !_submitting;

            // Watched rather than read so the count settles once the sidecar
            // answers; the same family key the settings screen uses, so opening
            // it costs no second request.
            final processRef = _processRef;
            final schema = ref.watch(processSchemaProvider).valueOrNull?.schema;
            final presetValues = processRef == null
                ? null
                : ref.watch(presetValuesProvider(processRef)).valueOrNull;
            final overrides = _overridesFrom(schema, presetValues);

            return ListView(
              shrinkWrap: true,
              children: [
                Text(l10n.sliceTitle, style: theme.textTheme.titleLarge),
                const SizedBox(height: 2),
                Text(widget.target.name,
                    style: theme.textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 16),
                _slotTile(
                  label: l10n.slicePrinter,
                  icon: Icons.print_outlined,
                  selected: _printer,
                  onTap: () async {
                    final p = await _openPicker(
                        title: l10n.slicePrinter,
                        filtered: printers,
                        all: presets.printers);
                    if (p != null && mounted) {
                      // Printer change can invalidate process/filament compatibility.
                      setState(() {
                        _printer = p;
                        _process = null;
                        _filaments = List.filled(_filaments.length, null);
                        // The edits were made against a preset that is gone.
                        _processValues = {};
                      });
                    }
                  },
                ),
                _slotTile(
                  label: l10n.sliceProcess,
                  icon: Icons.tune,
                  selected: _process,
                  onTap: () async {
                    final p = await _openPicker(
                        title: l10n.sliceProcess,
                        filtered: processes,
                        all: presets.processes);
                    if (p != null && mounted) setState(() => _process = p);
                  },
                ),
                Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    leading: const Icon(Icons.grid_on_outlined),
                    title: Text(l10n.sliceBedType,
                        style: theme.textTheme.labelMedium),
                    subtitle: Text(_bedType ?? l10n.sliceBedDefault,
                        style: theme.textTheme.bodyMedium),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _pickBedType,
                  ).tagged('slice.bed_type'),
                ),
                // Absent, not disabled, unless the server accepts
                // `process_overrides` *and* our own vendored metadata loaded —
                // `SliceRequest` forbids no extra fields, so an older server
                // would drop the whole map without a word.
                if (ref
                    .watch(processSettingsAvailableProvider)
                    .maybeWhen(data: (v) => v, orElse: () => false))
                  Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      leading: const Icon(Icons.tune_outlined),
                      enabled: processRef != null,
                      title: Text(l10n.processSettingsTitle,
                          style: theme.textTheme.labelMedium),
                      subtitle: Text(
                        processRef == null
                            ? l10n.sliceProcessSettingsNeedsProcess
                            : overrides.isEmpty
                                ? l10n.sliceProcessSettingsUnchanged
                                : l10n.sliceProcessSettingsChanged(
                                    overrides.length),
                        style: theme.textTheme.bodyMedium,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: processRef == null
                          ? null
                          : () => showProcessSettings(
                                context,
                                preset: processRef,
                                values: _processValues,
                                onChanged: (next) =>
                                    setState(() => _processValues = next),
                              ),
                    ).tagged('slice.process_settings'),
                  ),
                // Hidden entirely before server 1.2.6: the fields are dropped
                // without a word there, and a switch that does nothing is worse
                // than no switch. See [sliceLayoutOptionsProvider].
                if (ref
                    .watch(sliceLayoutOptionsProvider)
                    .maybeWhen(data: (v) => v, orElse: () => false)) ...[
                  Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      children: [
                        SwitchListTile(
                          value: _autoOrient,
                          onChanged: (v) => setState(() => _autoOrient = v),
                          secondary:
                              const Icon(Icons.screen_rotation_alt_outlined),
                          title: Text(l10n.sliceAutoOrient,
                              style: theme.textTheme.labelMedium),
                          subtitle: Text(l10n.sliceAutoOrientHint,
                              style: theme.textTheme.bodySmall),
                        ).tagged('slice.auto_orient'),
                        SwitchListTile(
                          value: _autoArrange,
                          onChanged: (v) => setState(() => _autoArrange = v),
                          secondary: const Icon(Icons.grid_view_outlined),
                          title: Text(l10n.sliceAutoArrange,
                              style: theme.textTheme.labelMedium),
                          subtitle: Text(l10n.sliceAutoArrangeHint,
                              style: theme.textTheme.bodySmall),
                        ).tagged('slice.auto_arrange'),
                      ],
                    ),
                  ),
                ],
                for (var i = 0; i < slotCount; i++)
                  _slotTile(
                    label: slotCount == 1
                        ? l10n.sliceFilament
                        : l10n.sliceFilamentNumbered('${i + 1}'),
                    icon: Icons.cable,
                    swatch: i < reqs.length ? colorFromHex(reqs[i].color) : null,
                    typeHint: i < reqs.length ? reqs[i].type : null,
                    selected: _filaments[i],
                    onTap: () async {
                      final p = await _openPicker(
                          title: slotCount == 1
                              ? l10n.sliceFilament
                              : l10n.sliceFilamentNumbered('${i + 1}'),
                          filtered: filaments,
                          all: presets.filaments);
                      if (p != null && mounted) setState(() => _filaments[i] = p);
                    },
                  ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.layers_outlined),
                  label: Text(l10n.sliceStart),
                  onPressed: ready ? _submit : null,
                ).tagged('slice.submit'),
              ],
            );
          },
        ),
      ),
    );
  }

  /// The picked process preset as `/slicer/preset-values` takes it.
  ProcessPresetRef? get _processRef =>
      _process == null ? null : (_process!.source, _process!.id);

  /// The `process_overrides` body: only the edits that really differ from what
  /// the picked preset already says. Empty until both the vendored schema and
  /// the preset's values are in hand — sending edits measured against an unknown
  /// baseline would mean sending values the user never chose to change.
  Map<String, Object> _overridesFrom(
    Map<String, ProcessOption>? schema,
    PresetValues? presetValues,
  ) {
    if (schema == null || presetValues == null) return const {};
    return buildProcessOverrides(
      values: _processValues,
      schema: schema,
      presetValues: presetValues.values,
    );
  }

  /// Grow/shrink the per-slot list, preserving existing picks.
  void _resizeFilaments(int count) {
    if (_filaments.length == count) return;
    final next = List<SlicerPreset?>.filled(count, null);
    for (var i = 0; i < count && i < _filaments.length; i++) {
      next[i] = _filaments[i];
    }
    _filaments = next;
  }

  Widget _slotTile({
    required String label,
    required IconData icon,
    required SlicerPreset? selected,
    required VoidCallback onTap,
    Color? swatch,
    String? typeHint,
  }) {
    final theme = Theme.of(context);
    final subtitle = selected?.name ??
        (typeHint != null ? '${_l10n.sliceSelect} · $typeHint' : _l10n.sliceSelect);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: swatch != null
            ? Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: swatch,
                  shape: BoxShape.circle,
                  border: Border.all(color: theme.dividerColor),
                ),
              )
            : Icon(icon),
        title: Text(label, style: theme.textTheme.labelMedium),
        subtitle: Text(subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color:
                  selected == null ? theme.colorScheme.onSurfaceVariant : null,
            )),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ).tagged('slice.slot'),
    );
  }

  Future<void> _pickBedType() async {
    final l10n = _l10n;
    // Sentinel '' = "Default (inherit from preset)" → stored as null.
    Widget tile(String value, String label) => ListTile(
          leading: Icon((_bedType ?? '') == value
              ? Icons.radio_button_checked
              : Icons.radio_button_unchecked),
          title: Text(label),
          onTap: () => Navigator.pop(context, value),
        ).tagged('slice.bed_type');
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            tile('', l10n.sliceBedDefault),
            for (final b in _bedTypes) tile(b, b),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return; // dismissed
    setState(() => _bedType = picked.isEmpty ? null : picked);
  }

  Future<SlicerPreset?> _openPicker({
    required String title,
    required List<SlicerPreset> filtered,
    required List<SlicerPreset> all,
  }) {
    return showModalBottomSheet<SlicerPreset>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PresetPicker(title: title, filtered: filtered, all: all),
    );
  }

  Future<void> _submit() async {
    final l10n = _l10n;
    final messenger = ScaffoldMessenger.of(context);
    final target = widget.target;
    final refs = [for (final f in _filaments) f!.toRef()];
    final overrides = _overridesFrom(
      ref.read(processSchemaProvider).valueOrNull?.schema,
      _processRef == null
          ? null
          : ref.read(presetValuesProvider(_processRef!)).valueOrNull,
    );
    final body = <String, dynamic>{
      'printer_preset': _printer!.toRef(),
      'process_preset': _process!.toRef(),
      // Single slot → the singular field (the proven path); multicolor → the
      // ordered array, one entry per filament slot.
      if (refs.length == 1)
        'filament_preset': refs.first
      else
        'filament_presets': refs,
      // Override the plate only when the user picked one; null inherits.
      if (_bedType != null) 'bed_type': _bedType,
      // Only when on: both default to false server-side, and an older server
      // ignores unknown keys silently, so sending the default would be noise
      // that also hides which servers actually honoured it.
      if (_autoOrient) 'auto_orient': true,
      if (_autoArrange) 'auto_arrange': true,
      // Only genuine deviations, so an untouched screen leaves this slice
      // byte-identical to one from before the feature existed.
      if (overrides.isNotEmpty) 'process_overrides': overrides,
    };
    setState(() => _submitting = true);
    final int jobId;
    try {
      final repo = ref.read(slicerRepositoryProvider);
      jobId = target.isArchive
          ? await repo.sliceArchive(target.id, body)
          : await repo.sliceLibraryFile(target.id, body);
    } on AppApiException catch (e) {
      if (mounted) setState(() => _submitting = false);
      showApiFailure(mounted ? messenger : null, e, l10n,
          action: 'slice.submit');
      return;
    }
    if (!mounted) return;
    final ok = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _SliceProgressDialog(jobId: jobId),
        ) ??
        false;
    if (!mounted) return;
    Navigator.pop(context, ok); // close the sheet, report success upward
  }

  // --- filtering / auto-pick ---

  SlicerPreset? _firstLocalOr(List<SlicerPreset> list) => list.isEmpty
      ? null
      : list.firstWhere((p) => p.isLocal, orElse: () => list.first);

  List<SlicerPreset> _filterPrinters(List<SlicerPreset> all, Set<String> codes) {
    if (codes.isEmpty) return all;
    return all
        .where((p) => p.isLocal || codes.any((c) => _containsCode(p.name, c)))
        .toList();
  }

  /// The owned code the selected printer maps to (drives process/filament compat).
  String? _codeOfPrinter(SlicerPreset printer, Set<String> codes) {
    for (final c in codes) {
      if (_containsCode(printer.name, c)) return c;
    }
    return null;
  }

  List<SlicerPreset> _filterProcesses(List<SlicerPreset> all, String? code) {
    if (code == null) return all;
    return all.where((p) => p.isLocal || _containsCode(p.name, code)).toList();
  }

  /// Owned (any material) + printer-compatible. Not narrowed by the model's
  /// filament type — the user can pick a different material per slot.
  List<SlicerPreset> _filterFilaments(
    List<SlicerPreset> all,
    String? code,
    List<OwnedFilament> owned,
  ) {
    bool compat(SlicerPreset p) => code == null || _containsCode(p.name, code);
    final ownedNames = {for (final o in owned) o.name};
    if (ownedNames.isEmpty) {
      // No owned-filament signal — narrow by printer only.
      return all.where((p) => p.isLocal || compat(p)).toList();
    }
    return all
        .where((p) =>
            p.isLocal || (_ownedMatch(p.name, ownedNames) && compat(p)))
        .toList();
  }

  /// Prefer the owned filament of the right material closest in colour to the
  /// requirement; fall back to a local preset, then the first option.
  SlicerPreset? _pickDefaultFilament(
    List<SlicerPreset> filtered,
    List<OwnedFilament> owned,
    FilamentRequirement? req,
  ) {
    if (filtered.isEmpty) return null;
    if (req != null) {
      final ofType = [
        for (final o in owned)
          if (req.type == null || _typeMatches(o.material, req.type!)) o,
      ]..sort((a, b) =>
          _colorDistance(a.color, req.color)
              .compareTo(_colorDistance(b.color, req.color)));
      for (final o in ofType) {
        final match = filtered.where((p) => p.name == o.name);
        if (match.isNotEmpty) return match.first;
      }
    }
    return _firstLocalOr(filtered);
  }
}

bool _typeMatches(String material, String type) {
  final m = material.toUpperCase();
  final t = type.toUpperCase();
  return m == t || m.startsWith(t) || t.startsWith(m);
}

/// Squared RGB distance between two colours; large when either is missing so
/// known colours win. Accepts `#RRGGBB` (requirement) and `RRGGBBAA` (spool).
double _colorDistance(String? a, String? b) {
  final ca = _rgb(a);
  final cb = _rgb(b);
  if (ca == null || cb == null) return double.maxFinite;
  final dr = ca.$1 - cb.$1, dg = ca.$2 - cb.$2, db = ca.$3 - cb.$3;
  return (dr * dr + dg * dg + db * db).toDouble();
}

/// Parse the leading `RRGGBB` of a hex colour (with or without `#`/alpha).
(int, int, int)? _rgb(String? hex) {
  if (hex == null) return null;
  var h = hex.trim();
  if (h.startsWith('#')) h = h.substring(1);
  if (h.length < 6) return null;
  final v = int.tryParse(h.substring(0, 6), radix: 16);
  if (v == null) return null;
  return ((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF);
}

/// A preset's name contains the printer [code] as a whole token, so "X1"
/// doesn't match "X1C". Case-insensitive; the code may contain a space
/// ("A1 Mini").
bool _containsCode(String name, String code) {
  final n = name.toUpperCase();
  final c = code.toUpperCase();
  if (c.isEmpty) return false;
  var i = n.indexOf(c);
  while (i >= 0) {
    final before = i == 0 ? ' ' : n[i - 1];
    final afterIdx = i + c.length;
    final after = afterIdx >= n.length ? ' ' : n[afterIdx];
    if (!_isAlnum(before) && !_isAlnum(after)) return true;
    i = n.indexOf(c, i + 1);
  }
  return false;
}

bool _isAlnum(String ch) => RegExp(r'[A-Za-z0-9]').hasMatch(ch);

/// A preset belongs to an owned filament if its name equals an owned base name
/// or extends it ("Bambu PETG HF" → "Bambu PETG HF @BBL X2D 0.4 nozzle").
bool _ownedMatch(String name, Set<String> owned) {
  for (final base in owned) {
    if (name == base || name.startsWith('$base ')) return true;
  }
  return false;
}

/// Searchable preset list with a "show all" escape hatch (the owned/compatible
/// filter is heuristic, so the full catalog is one toggle away).
class _PresetPicker extends StatefulWidget {
  const _PresetPicker({
    required this.title,
    required this.filtered,
    required this.all,
  });

  final String title;
  final List<SlicerPreset> filtered;
  final List<SlicerPreset> all;

  @override
  State<_PresetPicker> createState() => _PresetPickerState();
}

class _PresetPickerState extends State<_PresetPicker> {
  late bool _showAll = widget.filtered.isEmpty && widget.all.isNotEmpty;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final base = _showAll ? widget.all : widget.filtered;
    final q = _query.trim().toLowerCase();
    final items = q.isEmpty
        ? base
        : base.where((p) => p.name.toLowerCase().contains(q)).toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (ctx, scrollController) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child:
                        Text(widget.title, style: theme.textTheme.titleMedium),
                  ),
                  Text(l10n.sliceShowAll, style: theme.textTheme.bodySmall),
                  Switch(
                    value: _showAll,
                    onChanged: (v) => setState(() => _showAll = v),
                  ).tagged('slice.show_all_presets'),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: DashSearchField(
                id: 'slice.search',
                hintText: l10n.sliceSearchHint,
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          widget.filtered.isEmpty && !_showAll
                              ? l10n.sliceOwnedEmpty
                              : l10n.sliceNoPresets,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: items.length,
                      itemBuilder: (ctx, i) {
                        final p = items[i];
                        return ListTile(
                          dense: true,
                          title: Text(p.name,
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text(_sourceLabel(l10n, p.source)),
                          trailing: p.isLocal
                              ? Icon(Icons.star,
                                  size: 16, color: theme.colorScheme.primary)
                              : null,
                          onTap: () => Navigator.pop(ctx, p),
                        ).tagged('slice.preset_option');
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _sourceLabel(AppLocalizations l10n, String source) => switch (source) {
        'local' => l10n.sliceTierLocal,
        'cloud' => l10n.sliceTierCloud,
        'orca_cloud' => l10n.sliceTierOrcaCloud,
        _ => l10n.sliceTierStandard,
      };
}

/// Polls a slice job to completion, showing live stage/progress, then the
/// result (or error). Non-dismissible until terminal.
class _SliceProgressDialog extends ConsumerStatefulWidget {
  const _SliceProgressDialog({required this.jobId});
  final int jobId;

  @override
  ConsumerState<_SliceProgressDialog> createState() =>
      _SliceProgressDialogState();
}

class _SliceProgressDialogState extends ConsumerState<_SliceProgressDialog> {
  Timer? _timer;
  SliceJob? _job;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(const Duration(milliseconds: 1500), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    try {
      final job = await ref.read(slicerRepositoryProvider).job(widget.jobId);
      if (!mounted) return;
      setState(() => _job = job);
      if (job.isTerminal) _timer?.cancel();
    } on AppApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
      _timer?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final job = _job;
    final terminal = _error != null || (job?.isTerminal ?? false);
    final success = job?.isCompleted ?? false;

    Widget content;
    if (_error != null) {
      content = Text(_error is AppApiException
          ? (_error! as AppApiException).localized(l10n)
          : l10n.sliceFailed);
    } else if (job != null && job.isFailed) {
      content = Text(job.errorDetail ?? l10n.sliceFailed);
    } else if (success) {
      final r = job!.result;
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (r?.name != null)
            Text(r!.name!,
                style: theme.textTheme.bodyMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          if (r?.printTimeSeconds != null)
            Text(l10n.sliceResultTime(fmtDuration(r!.printTimeSeconds!))),
          if (r?.filamentUsedG != null)
            Text(l10n.sliceResultFilament(r!.filamentUsedG!.toStringAsFixed(1))),
        ],
      );
    } else {
      final stage = job?.progress?.stage;
      final fraction = job?.progress?.fraction;
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(value: fraction),
          const SizedBox(height: 12),
          Text(stage ?? l10n.sliceInProgress,
              style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
        ],
      );
    }

    return AlertDialog(
      title: Text(_error != null || (job?.isFailed ?? false)
          ? l10n.sliceFailed
          : success
              ? l10n.sliceDone
              : l10n.sliceInProgress),
      content: content,
      actions: terminal
          ? [
              logTag(
                'slice_progress.close',
                FilledButton(
                  onPressed: () => Navigator.pop(context, success),
                  child: Text(l10n.sliceClose),
                ),
              ),
            ]
          : null,
    );
  }
}
