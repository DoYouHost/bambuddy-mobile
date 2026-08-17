import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ams/filament_preset_catalog.dart';
import '../../../core/ams/printer_model_match.dart';
import '../../../core/ams/slot_configuration.dart';
import '../../../core/api/action_outcome.dart';
import '../../../core/diagnostics/log_tag.dart';
import '../../../core/models/ams_filament_preset.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers.dart';
import '../../common/confirm_dialog.dart';
import '../../../l10n/error_messages.dart';
import '../../inventory/inventory_screen.dart' show SpoolSwatch, parseSpoolColor;
import '../ams_slot_config_providers.dart';
import '../controls_providers.dart';

/// The slot the sheet configures, and what the card already knows about it.
///
/// Ids are local to the unit — the external spool is unit 255, slot 0 (Ext-L) or
/// 1 (Ext-R), the same pair the inventory assignment uses and the pair the
/// server turns back into `vt_tray` 254/255.
class AmsSlotTarget {
  const AmsSlotTarget({
    required this.printerId,
    required this.amsId,
    required this.trayId,
    required this.label,
    this.printerName,
    this.printerModel,
    this.nozzleDiameter,
    this.currentFilamentId,
    this.currentColour,
  });

  final int printerId;
  final int amsId;
  final int trayId;

  /// Readable slot name, e.g. "AMS 1 · 2".
  final String label;
  final String? printerName;

  /// Short model code (`X1C`), used to hide presets meant for another printer.
  final String? printerModel;

  /// From the printer's own report; `0.4` when it has not said. The guess lives
  /// here rather than in the model, which answers null so the gap stays visible.
  final String? nozzleDiameter;

  /// `tray_info_idx` the slot currently holds — identifies the preset in force
  /// when no saved mapping exists.
  final String? currentFilamentId;

  /// `RRGGBBAA` the slot currently shows, the colour the picker starts from.
  final String? currentColour;

  SlotKey get key =>
      (printerId: printerId, amsId: amsId, trayId: trayId);

  String get effectiveNozzleDiameter {
    final reported = nozzleDiameter?.trim();
    return (reported == null || reported.isEmpty) ? '0.4' : reported;
  }
}

/// Picks a filament preset and colour for one AMS slot and writes them to the
/// printer, with clearing the slot as the same sheet's undo.
///
/// The server computes none of this — see `SlotConfiguration` for what has to be
/// derived before the call — so everything the user chooses here ends up in the
/// query verbatim.
class AmsSlotConfigSheet extends ConsumerStatefulWidget {
  const AmsSlotConfigSheet({super.key, required this.target});

  final AmsSlotTarget target;

  @override
  ConsumerState<AmsSlotConfigSheet> createState() => _AmsSlotConfigSheetState();
}

class _AmsSlotConfigSheetState extends ConsumerState<AmsSlotConfigSheet> {
  final _search = TextEditingController();
  AmsFilamentPreset? _picked;
  String? _colour;

  /// Set once the saved mapping has been read, so reopening the sheet does not
  /// keep overwriting a pick the user just made.
  bool _preselected = false;

  @override
  void initState() {
    super.initState();
    _colour = _sixDigits(widget.target.currentColour);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final target = widget.target;
    final sources = ref.watch(slotPresetSourcesProvider);
    final saved = ref.watch(slotPresetProvider(target.key));

    _preselectFromSaved(sources.valueOrNull, saved.valueOrNull);

    return logTag(
      'sheet.ams_slot_config',
      DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text(l10n.amsSlotConfigTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              [?target.printerName, target.label].join(' · '),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            _colourField(l10n, theme),
            const SizedBox(height: 16),
            Text(l10n.amsSlotFilament, style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 20),
                labelText: l10n.amsSlotConfigSearch,
                border: const OutlineInputBorder(),
              ),
            ).tagged('ams_slot_config.search'),
            const SizedBox(height: 8),
            ...switch (sources) {
              AsyncError() => [_message(theme, l10n.amsSlotConfigEmpty)],
              AsyncLoading() => [
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ],
              AsyncValue(:final value?) => _presetList(l10n, theme, value),
              _ => const <Widget>[],
            },
            const SizedBox(height: 20),
            _actions(l10n),
          ],
        ),
      ),
    );
  }

  /// Preselect what the slot already holds, so the sheet opens showing the
  /// truth rather than an empty form the user has to re-fill to change a colour.
  void _preselectFromSaved(SlotPresetSources? sources, SlotPreset? saved) {
    if (_preselected || sources == null) return;
    _preselected = true;
    final wanted = saved?.presetId ?? widget.target.currentFilamentId;
    if (wanted == null || wanted.isEmpty) return;
    for (final preset in [...sources.local, ...sources.cloud, ...sources.builtin]) {
      if (preset.pickerId == wanted) {
        _picked = preset;
        return;
      }
    }
  }

  Widget _colourField(AppLocalizations l10n, ThemeData theme) => InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _pickColour(l10n),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: l10n.amsSlotConfigColour,
            border: const OutlineInputBorder(),
            suffixIcon: const Icon(Icons.colorize),
          ),
          child: Row(
            children: [
              SpoolSwatch(rgba: _colour, size: 24, radius: 6),
              const SizedBox(width: 12),
              Text(
                (_colour ?? 'FFFFFF').toUpperCase(),
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ).tagged('ams_slot_config.colour');

  List<Widget> _presetList(
    AppLocalizations l10n,
    ThemeData theme,
    SlotPresetSources sources,
  ) {
    final target = widget.target;
    final presets = filamentPresetCatalog(
      cloud: sources.cloud,
      local: sources.local,
      builtin: sources.builtin,
      query: _search.text,
      printerModel: target.printerModel,
      printerModels: sources.printerModels,
      fullPrinterName: target.printerModel == null
          ? null
          : fullPrinterPresetName(
              target.printerModel!,
              sources.printerModels,
              target.effectiveNozzleDiameter,
            ),
      savedPresetId: _picked?.pickerId,
      currentFilamentId: target.currentFilamentId,
    );

    return [
      if (sources.cloudNeedsLogin) _cloudLoginHint(l10n, theme),
      if (presets.isEmpty)
        _message(
          theme,
          sources.isEmpty ? l10n.amsSlotConfigEmpty : l10n.amsSlotConfigNoMatch,
        )
      else
        for (final preset in presets)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            selected: _picked?.pickerId == preset.pickerId,
            onTap: () => setState(() => _picked = preset),
            leading: Icon(
              _picked?.pickerId == preset.pickerId
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 20,
            ),
            title: Text(preset.name, maxLines: 2,
                overflow: TextOverflow.ellipsis),
            subtitle: Text(_tierLabel(l10n, preset.source)),
          ).taggedMaterial('ams_slot_config.preset', preset.sourceKey),
    ];
  }

  Widget _cloudLoginHint(AppLocalizations l10n, ThemeData theme) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: const Icon(Icons.cloud_off),
          title: Text(l10n.amsSlotConfigCloudHint,
              style: theme.textTheme.bodySmall),
          trailing: TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pushNamed('/settings/cloud');
            },
            child: Text(l10n.amsSlotConfigCloudAction),
          ).tagged('ams_slot_config.cloud_login'),
        ),
      );

  Widget _message(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          text,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      );

  Widget _actions(AppLocalizations l10n) {
    final busy = ref.watch(controlsProvider.select(
        (s) => s.pendingFor(widget.target.printerId).isBusy(ControlAction.ams)));
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: busy ? null : () => _reset(l10n),
            icon: const Icon(Icons.layers_clear, size: 18),
            label: Text(l10n.amsSlotReset),
          ).tagged('ams_slot_config.reset'),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton.icon(
            onPressed: busy || _picked == null ? null : () => _apply(l10n),
            icon: const Icon(Icons.check, size: 18),
            label: Text(l10n.amsSlotConfigApply),
          ).tagged('ams_slot_config.apply'),
        ),
      ],
    );
  }

  Future<void> _pickColour(AppLocalizations l10n) async {
    var picked = parseSpoolColor(_colour) ?? const Color(0xFFFFFFFF);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.amsSlotConfigColour),
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: picked,
            onColorChanged: (c) => picked = c,
            // The printer has no use for a transparent filament: a zero alpha
            // is how it reports an *empty* slot, so the picker never offers it.
            enableAlpha: false,
            hexInputBar: true,
            labelTypes: const [],
            portraitOnly: true,
            pickerAreaHeightPercent: 0.7,
          ),
        ),
        actions: [
          logTag(
            'ams_slot_colour.cancel',
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.cancel),
            ),
          ),
          logTag(
            'ams_slot_colour.confirm',
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.inventoryColorSelect),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _colour =
        (picked.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase());
  }

  Future<void> _apply(AppLocalizations l10n) async {
    final preset = _picked;
    if (preset == null) return;
    final target = widget.target;

    // Read before building the request, not inside it: for a user's own cloud
    // preset the detail carries the filament id the printer resolves, and the
    // one derived from the setting id would collapse the slot to the generic it
    // inherits from. Best effort — null just means we fall back to that.
    final cloudFilamentId = preset.source == AmsPresetSource.cloud
        ? await ref.read(amsSlotConfigRepositoryProvider).cloudFilamentId(preset.id)
        : null;
    if (!mounted) return;

    final configuration = SlotConfiguration.forPreset(
      preset: preset,
      colourHex: _colour ?? 'FFFFFF',
      nozzleDiameter: target.effectiveNozzleDiameter,
      cloudFilamentId: cloudFilamentId,
    );

    await _send(
      l10n,
      () => ref.read(controlsProvider.notifier).configureSlot(
            target.printerId,
            amsId: target.amsId,
            trayId: target.trayId,
            preset: preset,
            configuration: configuration,
          ),
      l10n.amsSlotConfigStarted,
    );
  }

  Future<void> _reset(AppLocalizations l10n) async {
    final target = widget.target;
    final confirmed = await confirmDialog(
      context,
      title: l10n.amsSlotResetConfirmTitle,
      message: l10n.amsSlotResetConfirmMessage,
      confirmLabel: l10n.amsSlotReset,
      destructive: true,
      id: 'ams_slot_reset',
    );
    if (!confirmed || !mounted) return;
    await _send(
      l10n,
      () => ref.read(controlsProvider.notifier).resetSlot(
            target.printerId,
            amsId: target.amsId,
            trayId: target.trayId,
          ),
      l10n.amsSlotResetStarted,
    );
  }

  /// Runs a command, closes the sheet and reports the outcome.
  ///
  /// Closing first, like the load/unload actions: the printer takes seconds to
  /// act and its answer arrives over the socket, so there is nothing here left
  /// to watch. The saved mapping is invalidated either way — a failed write may
  /// still have cleared it.
  Future<void> _send(
    AppLocalizations l10n,
    Future<ActionOutcome> Function() send,
    String startedMessage,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final outcome = await send();
    ref.invalidate(slotPresetProvider(widget.target.key));
    if (!mounted) return;
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(content: Text(outcome.messageFor(l10n) ?? startedMessage)),
    );
  }

  String _tierLabel(AppLocalizations l10n, AmsPresetSource source) =>
      switch (source) {
        AmsPresetSource.local => l10n.amsSlotConfigTierLocal,
        AmsPresetSource.cloud => l10n.amsSlotConfigTierCloud,
        AmsPresetSource.builtin => l10n.amsSlotConfigTierBuiltin,
      };
}

/// Six hex digits from a stored `RRGGBBAA`, or null when there is nothing to
/// start from. The alpha is dropped: it is re-added on the way out, and an empty
/// slot's `00` must not become the colour the picker opens on.
String? _sixDigits(String? rgba) {
  final raw = rgba?.trim().replaceFirst('#', '');
  if (raw == null || raw.length < 6) return null;
  final rgb = raw.substring(0, 6).toUpperCase();
  return RegExp(r'^[0-9A-F]{6}$').hasMatch(rgb) ? rgb : null;
}
