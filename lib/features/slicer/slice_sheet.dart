import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/models/slice_job.dart';
import '../../core/models/slicer_preset.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import '../../providers.dart';
import '../stats/stats_common.dart' show fmtDuration;
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

class _SliceSheetState extends ConsumerState<_SliceSheet> {
  SlicerPreset? _printer;
  SlicerPreset? _process;
  SlicerPreset? _filament;
  bool _submitting = false;

  AppLocalizations get _l10n => AppLocalizations.of(context);

  /// Auto-pick the first option of a slot once presets load, preferring the
  /// user's local presets (they own that printer).
  void _autoPick(List<SlicerPreset> printers, List<SlicerPreset> processes,
      List<SlicerPreset> filaments) {
    SlicerPreset? first(List<SlicerPreset> list) =>
        list.isEmpty ? null : list.firstWhere((p) => p.isLocal, orElse: () => list.first);
    _printer ??= first(printers);
    _process ??= first(processes);
    _filament ??= first(filaments);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n;
    final theme = Theme.of(context);
    final presetsAsync = ref.watch(slicerPresetsProvider);
    final ownedCodes =
        ref.watch(ownedPrinterCodesProvider).valueOrNull ?? const <String>{};
    final ownedFilaments =
        ref.watch(ownedFilamentNamesProvider).valueOrNull ?? const <String>{};

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
            final printers = _filterPrinters(presets.printers, ownedCodes);
            final code = _printer == null
                ? null
                : _codeOfPrinter(_printer!, ownedCodes);
            final processes = _filterProcesses(presets.processes, code);
            final filaments =
                _filterFilaments(presets.filaments, code, ownedFilaments);
            _autoPick(printers, processes, filaments);

            final ready = _printer != null &&
                _process != null &&
                _filament != null &&
                !_submitting;

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
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
                      all: presets.printers,
                    );
                    if (p != null) {
                      // Printer change can invalidate process/filament compatibility.
                      setState(() {
                        _printer = p;
                        _process = null;
                        _filament = null;
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
                      all: presets.processes,
                    );
                    if (p != null) setState(() => _process = p);
                  },
                ),
                _slotTile(
                  label: l10n.sliceFilament,
                  icon: Icons.cable,
                  selected: _filament,
                  onTap: () async {
                    final p = await _openPicker(
                      title: l10n.sliceFilament,
                      filtered: filaments,
                      all: presets.filaments,
                    );
                    if (p != null) setState(() => _filament = p);
                  },
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.layers_outlined),
                    label: Text(l10n.sliceStart),
                    onPressed: ready ? _submit : null,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _slotTile({
    required String label,
    required IconData icon,
    required SlicerPreset? selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Icon(icon),
        title: Text(label, style: theme.textTheme.labelMedium),
        subtitle: Text(
          selected?.name ?? _l10n.sliceSelect,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: selected == null ? theme.colorScheme.onSurfaceVariant : null,
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
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
    final body = <String, dynamic>{
      'printer_preset': _printer!.toRef(),
      'process_preset': _process!.toRef(),
      'filament_preset': _filament!.toRef(),
    };
    setState(() => _submitting = true);
    final int jobId;
    try {
      final repo = ref.read(slicerRepositoryProvider);
      jobId = target.isArchive
          ? await repo.sliceArchive(target.id, body)
          : await repo.sliceLibraryFile(target.id, body);
    } on AppApiException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      messenger.showSnackBar(SnackBar(content: Text(e.localized(l10n))));
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

  // --- filtering ---

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
    return all
        .where((p) => p.isLocal || _containsCode(p.name, code))
        .toList();
  }

  List<SlicerPreset> _filterFilaments(
      List<SlicerPreset> all, String? code, Set<String> owned) {
    bool compat(SlicerPreset p) => code == null || _containsCode(p.name, code);
    if (owned.isEmpty) {
      // No owned-filament signal (e.g. Spoolman) — narrow by printer only.
      return all.where((p) => p.isLocal || compat(p)).toList();
    }
    return all
        .where((p) => p.isLocal || (_ownedMatch(p.name, owned) && compat(p)))
        .toList();
  }
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
                    child: Text(widget.title,
                        style: theme.textTheme.titleMedium),
                  ),
                  Text(l10n.sliceShowAll, style: theme.textTheme.bodySmall),
                  Switch(
                    value: _showAll,
                    onChanged: (v) => setState(() => _showAll = v),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SearchBar(
                hintText: l10n.sliceSearchHint,
                leading: const Icon(Icons.search),
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
                        );
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
    _timer =
        Timer.periodic(const Duration(milliseconds: 1500), (_) => _poll());
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
              FilledButton(
                onPressed: () => Navigator.pop(context, success),
                child: Text(l10n.sliceClose),
              ),
            ]
          : null,
    );
  }
}
