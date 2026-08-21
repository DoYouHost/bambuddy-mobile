import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/ams/filament_naming.dart';
import '../../../core/ams/filament_preset_catalog.dart';
import '../../../core/ams/k_profile_match.dart';
import '../../../core/ams/preset_colours.dart';
import '../../../core/ams/printer_model_match.dart';
import '../../../core/ams/slot_configuration.dart';
import '../../../core/api/action_outcome.dart';
import '../../../core/diagnostics/log_tag.dart';
import '../../../core/models/ams_filament_preset.dart';
import '../../../core/models/inventory_reference.dart';
import '../../../core/models/k_profile.dart';
import '../../../core/theme/dash_text.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers.dart';
import '../../../core/theme/dash_theme.dart';
import '../../common/confirm_dialog.dart';
import '../../common/dash_input.dart';
import '../../../l10n/error_messages.dart';
import '../../inventory/inventory_providers.dart' show colorCatalogProvider;
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
    this.currentCaliIdx,
    this.extruderId,
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

  /// `cali_idx` the slot is printing with — the calibration profile to
  /// preselect, so reopening the sheet does not offer to drop it.
  final int? currentCaliIdx;

  /// Which nozzle this slot feeds on a dual-extruder printer, null on a single
  /// one. Only tells apart the duplicate calibration rows such a printer
  /// reports.
  final int? extruderId;

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

  /// Set once preselection has actually found the slot's preset. Deliberately
  /// not set when it finds nothing: the preset may simply be hidden by the
  /// printer filter, and turning that off has to give it another chance.
  bool _preselected = false;

  /// The user has chosen a preset themselves, which nothing may overwrite.
  bool _userPicked = false;

  /// [SlotPreset.presetId] the server remembers for this slot, once it answers.
  String? _savedPresetId;

  /// What the slot was already set to when the sheet opened, if the picker
  /// could name it. Deliberately not `_picked`: it is fixed for the life of the
  /// sheet, so the row stays where it is while the user browses.
  String? _currentPresetId;

  /// Hide presets whose name names a different printer. On by default: a cloud
  /// account carries every preset for every printer its owner has, and an
  /// unfiltered list is mostly noise.
  bool _onlyThisPrinter = true;

  /// Calibration profile to select, null for the printer's default K.
  KProfile? _kProfile;

  /// Which preset [_kProfile] was chosen under — `''` for "none picked yet".
  ///
  /// Null while the printer's calibration table is still loading, which is what
  /// keeps the default from being decided against an empty list and then never
  /// revisited.
  String? _kProfileFor;

  /// Whether the user answered the calibration question for the filament now
  /// picked. False means they were never really asked — the table failed to
  /// load, or held nothing for this nozzle — and the slot keeps whatever
  /// calibration it already has instead of being reset to the printer default.
  bool _kProfileAnswered = false;

  @override
  void initState() {
    super.initState();
    _colour = sixHexDigits(widget.target.currentColour);
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
    final t = DashTokens.of(context);
    final target = widget.target;
    final sources = ref.watch(slotPresetSourcesProvider);
    final saved = ref.watch(slotPresetProvider(target.key));

    _savedPresetId = saved.valueOrNull?.presetId;

    final view = sources.valueOrNull == null
        ? null
        : _view(sources.requireValue);

    // After `_view`, which is where the preset gets preselected: the profiles
    // on offer are the ones that fit whatever is picked.
    final table = ref
        .watch(kProfilesProvider((
          printerId: target.printerId,
          nozzleDiameter: target.effectiveNozzleDiameter,
        )))
        .valueOrNull;
    final choices =
        table == null ? null : _kProfileChoices(table.profiles);
    // Three bands, and only the middle one scrolls: what the slot is and what
    // is being searched stay put, the catalogue moves under them, and the
    // actions stay reachable. One scroll region for a form, a filter and a
    // thousand-row list put all three on the same journey.
    return logTag(
      'sheet.ams_slot_config',
      FractionallySizedBox(
        // Fill what the modal allows (90% of the screen). The bands below need
        // a bounded height to divide, and a sheet that sizes itself to its
        // content would jump between a two-row list and a thousand-row one.
        heightFactor: 1,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l10n.amsSlotConfigTitle,
                      style: theme.textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    [?target.printerName, target.label].join(' · '),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _colourField(l10n, t),
                  const SizedBox(height: 12),
                  _kProfileField(l10n, t, choices, failed: table?.failed),
                  const SizedBox(height: 16),
                  Text(l10n.amsSlotFilament, style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    style: t.bodyPlain.copyWith(color: t.textPrimary),
                    decoration: dashDecoration(
                      t,
                      hintText: l10n.amsSlotConfigSearch,
                      prefixIcon:
                          Icon(Icons.search, size: 18, color: t.textTertiary),
                    ),
                  ).tagged('ams_slot_config.search'),
                  if (view != null) ...[
                    const SizedBox(height: 8),
                    ..._filterRow(l10n, t, view),
                  ],
                ],
              ),
            ),
            Expanded(
              child: switch (sources) {
                AsyncLoading() =>
                  const Center(child: CircularProgressIndicator()),
                AsyncError() => _scrollableMessage(t, l10n.amsSlotConfigEmpty),
                _ => _presetList(l10n, t, view!),
              },
            ),
            _actions(l10n, t),
          ],
        ),
      ),
    );
  }

  /// Preselect what the slot already holds, so the sheet opens showing the
  /// truth rather than an empty form the user has to re-fill to change a colour.
  ///
  /// Two sources, in this order:
  ///
  /// 1. the server's slot→preset mapping, which is the only thing that can name
  ///    a *user's own* cloud preset;
  /// 2. failing that, the filament id the printer itself reports.
  ///
  /// The mapping goes first because it is more specific, but it is not trusted
  /// blindly: saving it needs `printers:update` and a refusal leaves the
  /// *previous* preset on file, so a mapping that names nothing in the visible
  /// list is dropped rather than forced into it. Candidates come from the list
  /// as rendered — arming the write with a row the user cannot see is how a slot
  /// gets configured with a preset nobody chose.
  void _preselectFrom(List<AmsFilamentPreset> visible) {
    if (_preselected || _userPicked || visible.isEmpty) return;

    final loaded = widget.target.currentFilamentId;
    final mapped = _savedPresetId;
    if (mapped != null && mapped.isNotEmpty) {
      for (final preset in visible) {
        if (preset.pickerId != mapped) continue;
        // Unless the printer says otherwise. A mapping only goes stale in one
        // direction — nothing rewrites it when the slot changes by another
        // route, and on an API key nothing rewrites it at all — so a filament
        // id that disagrees is the mapping being out of date, not the printer.
        if (!_contradicts(preset, loaded)) {
          _picked = preset;
          _currentPresetId = preset.pickerId;
          _preselected = true;
          return;
        }
        break;
      }
    }

    if (loaded == null || loaded.isEmpty) return;
    for (final preset in visible) {
      if (_filamentIdOf(preset) == loaded) {
        _picked = preset;
        _currentPresetId = preset.pickerId;
        _preselected = true;
        return;
      }
    }
  }

  /// Lift what the slot is already set to to the top of the list.
  ///
  /// It is the row the user came to look at, and in a catalogue this size it
  /// otherwise lands wherever the alphabet puts it — three screens down, among
  /// six near-identical names. Pinned by the preset the sheet *opened* on, not
  /// by the current selection, so the list does not rearrange itself under a
  /// finger that is still choosing.
  List<AmsFilamentPreset> _currentFirst(List<AmsFilamentPreset> presets) {
    final pinned = _currentPresetId;
    if (pinned == null) return presets;
    final at = presets.indexWhere((p) => p.pickerId == pinned);
    if (at <= 0) return presets;
    return [
      presets[at],
      ...presets.sublist(0, at),
      ...presets.sublist(at + 1),
    ];
  }

  /// Whether [preset] names a different filament than the one the slot reports.
  ///
  /// Only comparable when the preset resolves to a Bambu filament id: a user's
  /// own cloud preset resolves to its own id, which the list cannot derive, so
  /// silence there means "no evidence", not "disagreement".
  bool _contradicts(AmsFilamentPreset preset, String? loaded) {
    if (loaded == null || loaded.isEmpty) return false;
    final id = _filamentIdOf(preset);
    if (id == null || !id.startsWith('GF') || !loaded.startsWith('GF')) {
      return false;
    }
    return id != loaded;
  }

  /// The Bambu filament id behind a preset, or null when it has none — an
  /// imported preset carries no Bambu id at all.
  String? _filamentIdOf(AmsFilamentPreset preset) => switch (preset.source) {
        AmsPresetSource.cloud => filamentIdFromSettingId(preset.id),
        AmsPresetSource.builtin => preset.id,
        AmsPresetSource.local => null,
      };

  /// Same shape as the spool form's colour field — swatch, mono hex, eyedropper
  /// — so the two read as one control in two places.
  Widget _colourField(AppLocalizations l10n, DashTokens t) => InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _pickColour(l10n),
        child: InputDecorator(
          decoration: dashDecoration(
            t,
            labelText: l10n.amsSlotConfigColour,
            suffixIcon: Icon(Icons.colorize, color: t.textTertiary),
          ),
          child: Row(
            children: [
              SpoolSwatch(rgba: _colour, size: 24, radius: 6),
              const SizedBox(width: 8),
              Text(
                (_colour ?? 'FFFFFF').toUpperCase(),
                style: t.monoValue,
              ),
            ],
          ),
        ),
      ).tagged('ams_slot_config.colour');

  /// The calibration profiles on offer for whatever preset is picked, and the
  /// selection kept in step with it.
  KProfileChoices _kProfileChoices(List<KProfile> profiles) {
    final preset = _picked;
    final choices = matchKProfiles(
      profiles: profiles,
      presetName: preset?.name,
      presetFilamentId: preset == null ? null : _filamentIdOf(preset),
      extruderId: widget.target.extruderId,
      activeCaliIdx: widget.target.currentCaliIdx,
    );

    // A profile calibrated for one filament means nothing for another, so
    // changing the preset re-derives the pick rather than carrying it over.
    final forPreset = _picked?.pickerId ?? '';
    if (_kProfileFor != forPreset) {
      _kProfileFor = forPreset;
      _kProfile = _defaultKProfile(choices);
      // A decision made about the previous filament says nothing about this
      // one, so the question reopens with it.
      _kProfileAnswered = _kProfile != null;
    }
    return choices;
  }

  /// Which profile a freshly picked preset arms.
  ///
  /// The slot's own profile first: leaving it unselected would write the
  /// printer back to its default K and quietly undo a calibration the user did.
  /// Failing that the best match, which is what the picker was filtered down to
  /// — the web does the same, and a slot left on the default when a profile
  /// exists for that exact filament prints worse for no reason.
  KProfile? _defaultKProfile(KProfileChoices choices) {
    final active = widget.target.currentCaliIdx;
    if (active != null) {
      for (final profile in choices.matching) {
        if (profile.slotId == active) return profile;
      }
    }
    return choices.matching.isEmpty ? null : choices.matching.first;
  }

  /// Pressure advance, as a select: the matching profiles, then everything else
  /// the printer holds under a heading of its own.
  ///
  /// The residual group is not padding. The match runs on names the user typed
  /// in the slicer and on filament ids, so a profile named after its colour can
  /// fall outside it — and the printer's table, not our guess, is what can
  /// actually be selected.
  ///
  /// Shown even when there is nothing to choose from — an empty table and a
  /// refused read both used to hide the control, which reads as the feature
  /// being missing rather than as the printer having no calibrations. Disabled
  /// and labelled instead, so the answer is on screen either way.
  /// [choices] is null while the table is still being read, [failed] null with
  /// it.
  Widget _kProfileField(
    AppLocalizations l10n,
    DashTokens t,
    KProfileChoices? choices, {
    required bool? failed,
  }) {
    DropdownMenuEntry<String> entry(String value, String label,
            {bool enabled = true}) =>
        DropdownMenuEntry(
          value: value,
          label: label,
          enabled: enabled,
          // The menu opens in a route of its own, so the field's own tag does
          // not reach it. The label is a user-chosen profile name and stays out
          // of the identifier.
          labelWidget: logTag('ams_slot_config.k_profile.option', Text(label)),
        );

    // Three decimals, the precision the slicer calibrates to, through the
    // locale's own separator — the default entry sits in the same list and
    // reads "K 0,020" in Polish, so a hard-coded dot beside it looks broken.
    final k = NumberFormat('0.000', l10n.localeName);
    String labelFor(KProfile p) =>
        '${p.name} · ${l10n.amsSlotConfigKProfileValue(k.format(p.k))}';

    final matching = choices?.matching ?? const <KProfile>[];
    final other = choices?.other ?? const <KProfile>[];

    return dashCombo<String>(
      context,
      id: 'ams_slot_config.k_profile',
      initialSelection: _kProfile?.optionId ?? '',
      label: Text(l10n.amsSlotConfigKProfile),
      // Says why there is nothing to pick, which the field alone cannot: an
      // unread table, a guessed nozzle and an uncalibrated printer all leave it
      // on "default" and are three different problems.
      helperText: switch ((failed, matching.isEmpty && other.isEmpty)) {
        (null, _) => null,
        (true, _) => l10n.amsSlotConfigKProfileUnavailable,
        // The guess drives a real query now — the calibration table is indexed
        // by nozzle size — so a printer that never said which nozzle it wears
        // may be answering about the wrong one. Also what the write sends.
        _ when widget.target.nozzleDiameter == null => l10n
            .amsSlotConfigNozzleGuess(widget.target.effectiveNozzleDiameter),
        (false, true) => l10n.amsSlotConfigKProfileNone,
        (false, false) => null,
      },
      enabled: matching.isNotEmpty || other.isNotEmpty,
      textStyle: t.body,
      onSelected: (value) => setState(() {
        _kProfile = choices?.byOptionId(value);
        _kProfileAnswered = true;
      }),
      entries: [
        entry('', l10n.amsSlotConfigKProfileDefault(k.format(_defaultK))),
        for (final p in matching) entry(p.optionId, labelFor(p)),
        if (other.isNotEmpty) ...[
          // A disabled row is the menu's only grouping device.
          entry(_otherProfilesHeading, l10n.amsSlotConfigKProfileOther,
              enabled: false),
          for (final p in other) entry(p.optionId, labelFor(p)),
        ],
      ],
    );
  }

  /// What the picker shows for the current search and filter state, plus what
  /// the filter is costing. Computed once in `build` because the header needs
  /// the count and the body needs the rows.
  _CatalogueView _view(SlotPresetSources sources) {
    final target = widget.target;
    final model = target.printerModel;

    List<AmsFilamentPreset> catalogue({required bool forThisPrinter}) =>
        filamentPresetCatalog(
          cloud: sources.cloud,
          local: sources.local,
          builtin: sources.builtin,
          query: _search.text,
          printerModel: forThisPrinter ? model : null,
          printerModels: sources.printerModels,
          fullPrinterName: !forThisPrinter || model == null
              ? null
              : fullPrinterPresetName(
                  model,
                  sources.printerModels,
                  target.effectiveNozzleDiameter,
                ),
        );

    // Both lists, always: the count of what the filter takes away is the only
    // honest label for the switch that turns it off.
    final everything = catalogue(forThisPrinter: false);
    final canFilter = model != null && model.isNotEmpty;
    final presets = canFilter && _onlyThisPrinter
        ? catalogue(forThisPrinter: true)
        : everything;

    // Preselect here rather than after: pinning the current preset needs to
    // know which one it is, and both answers come off the same list.
    _preselectFrom(presets);

    return (
      presets: _currentFirst(presets),
      hidden: everything.length - presets.length,
      model: canFilter ? model : null,
      anyPresetAtAll: !sources.isEmpty,
      cloudNeedsLogin: sources.cloudNeedsLogin,
    );
  }

  /// The part of the header that depends on the catalogue: the cloud-login
  /// offer and the printer filter.
  List<Widget> _filterRow(
      AppLocalizations l10n, DashTokens t, _CatalogueView view) {
    final model = view.model;
    return [
      if (view.cloudNeedsLogin) _cloudLoginHint(l10n, t),
      if (model != null)
        _printerFilterChip(l10n, t, model: model, hidden: view.hidden)
      else if (view.anyPresetAtAll)
        // Without a model there is nothing to match preset names against, so
        // the list is unfiltered — said out loud rather than left to look like
        // a filter that does nothing.
        _message(t, l10n.amsSlotConfigModelUnknown),
    ];
  }

  /// The scrolling band: only the presets, so the form above and the actions
  /// below stay where the user left them.
  Widget _presetList(AppLocalizations l10n, DashTokens t, _CatalogueView view) {
    if (view.presets.isEmpty) {
      return _scrollableMessage(
        t,
        view.anyPresetAtAll
            ? l10n.amsSlotConfigNoMatch
            : l10n.amsSlotConfigEmpty,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      itemCount: view.presets.length,
      itemBuilder: (_, i) => _presetTile(l10n, t, view.presets[i]),
    );
  }

  /// A message where the list would be. Scrollable so the sheet still gives on
  /// a drag, and so a long line has somewhere to go on a short screen.
  Widget _scrollableMessage(DashTokens t, String text) => ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [_message(t, text)],
      );

  /// Toggle between "presets for this printer" and everything the account has.
  ///
  /// Filtering is on by default — a cloud account holds every preset for every
  /// printer its owner has ever used — but the classification is name-based and
  /// therefore fallible, so there has to be a way past it.
  Widget _printerFilterChip(
    AppLocalizations l10n,
    DashTokens t, {
    required String model,
    required int hidden,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FilterChip(
            selected: _onlyThisPrinter,
            onSelected: (v) => setState(() => _onlyThisPrinter = v),
            avatar: Icon(
              _onlyThisPrinter ? Icons.filter_alt : Icons.filter_alt_off,
              size: 18,
              color: _onlyThisPrinter ? t.accentGreenInk : t.textTertiary,
            ),
            showCheckmark: false,
            label: Text(
              _onlyThisPrinter && hidden > 0
                  ? l10n.amsSlotConfigOnlyPrinterHiding(model, hidden)
                  : l10n.amsSlotConfigOnlyPrinter(model),
            ),
          ).tagged('ams_slot_config.only_this_printer'),
        ),
      );

  /// One preset row, in the card-list shape the rest of the dashboard uses:
  /// a filled [DashTokens.subCard] block that turns accent-bordered when picked,
  /// rather than a bare Material tile with a radio glued to it.
  Widget _presetTile(
    AppLocalizations l10n,
    DashTokens t,
    AmsFilamentPreset preset,
  ) {
    final selected = _picked?.pickerId == preset.pickerId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() {
          _picked = preset;
          _userPicked = true;
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: t.subCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? t.accentGreen : t.subCardBorder,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                size: 18,
                color: selected ? t.accentGreenInk : t.textTertiary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      preset.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.body,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      // Says why this one is at the top, so the pinning does
                      // not read as the sort being broken.
                      preset.pickerId == _currentPresetId
                          ? '${l10n.amsSlotConfigCurrent} · '
                              '${_tierLabel(l10n, preset.source)}'
                          : _tierLabel(l10n, preset.source),
                      style: t.microSoft.copyWith(color: preset.pickerId == _currentPresetId
                            ? t.accentGreenInk
                            : t.textTertiary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ).taggedMaterial('ams_slot_config.preset', preset.sourceKey);
  }

  Widget _cloudLoginHint(AppLocalizations l10n, DashTokens t) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(
          color: t.accentBlue.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: t.accentBlue.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(Icons.cloud_off, size: 18, color: t.accentBlue),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.amsSlotConfigCloudHint,
                style: t.labelSoft.copyWith(color: t.textPrimary),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pushNamed('/settings/cloud');
              },
              child: Text(l10n.amsSlotConfigCloudAction),
            ).tagged('ams_slot_config.cloud_login'),
          ],
        ),
      );

  Widget _message(DashTokens t, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          text,
          style: TextStyle(
            fontFamily: DashTokens.fontUi,
            fontSize: 13,
            color: t.textTertiary,
          ),
        ),
      );

  /// The pinned foot of the sheet: full-width primary action with the
  /// destructive one below it, rather than two halves of a row — "Zapisz w
  /// drukarce" does not fit half a phone width and wraps onto two lines there.
  ///
  /// Opaque and hairline-topped, because the list scrolls underneath it. The
  /// button takes the theme's own [dashPrimaryButtonStyle] by way of
  /// `filledButtonTheme`, so it matches every other confirming button without
  /// restating the style.
  Widget _actions(AppLocalizations l10n, DashTokens t) {
    final busy = ref.watch(controlsProvider.select(
        (s) => s.pendingFor(widget.target.printerId).isBusy(ControlAction.ams)));
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: t.overlaySurface,
        border: Border(top: BorderSide(color: t.overlayBorder)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton(
              onPressed: busy || _picked == null ? null : () => _apply(l10n),
              child: busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.amsSlotConfigApply),
            ).tagged('ams_slot_config.apply'),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: busy ? null : () => _reset(l10n),
              icon: const Icon(Icons.layers_clear, size: 18),
              label: Text(l10n.amsSlotReset),
              style: TextButton.styleFrom(foregroundColor: t.danger),
            ).tagged('ams_slot_config.reset'),
          ],
        ),
      ),
    );
  }

  Future<void> _pickColour(AppLocalizations l10n) async {
    final chosen = await showDialog<String>(
      context: context,
      builder: (_) => _ColourDialog(
        initial: _colour,
        // The colours a filament is sold in only mean something once the
        // filament is known.
        presetName: _picked?.name,
      ),
    );
    if (chosen == null || !mounted) return;
    setState(() => _colour = chosen);
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
      kProfile: _kProfile,
      // Only when the picker never got to put the question: writing the
      // default over a calibration nobody was shown throws away work that
      // costs a recalibration to get back.
      keepCaliIdx: _kProfileAnswered ? null : target.currentCaliIdx,
    );

    SlotConfigOutcome? result;
    await _send(
      l10n,
      () async {
        result = await ref.read(controlsProvider.notifier).configureSlot(
              target.printerId,
              amsId: target.amsId,
              trayId: target.trayId,
              preset: preset,
              configuration: configuration,
            );
        return result!.outcome;
      },
      // A refusal is worth a word — the slot keeps the previous name and the
      // sheet will show it next time. "Unavailable" is not: on an API key the
      // route can never succeed, and there is nothing the user could do with
      // the warning except see it after every save.
      () => result?.name == SlotNameOutcome.refused
          ? l10n.amsSlotConfigNameNotSaved
          : l10n.amsSlotConfigStarted,
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
      () => l10n.amsSlotResetStarted,
    );
  }

  /// Runs a command, closes the sheet and reports the outcome.
  ///
  /// Closing first, like the load/unload actions: the printer takes seconds to
  /// act and its answer arrives over the socket, so there is nothing here left
  /// to watch. The saved mapping is invalidated either way — a failed write may
  /// still have cleared it.
  ///
  /// [succeeded] is a callback, not a string, because what "it worked" should
  /// say can depend on what the command found out along the way.
  Future<void> _send(
    AppLocalizations l10n,
    Future<ActionOutcome> Function() send,
    String Function() succeeded,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final outcome = await send();
    ref.invalidate(slotPresetProvider(widget.target.key));
    if (!mounted) return;
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(content: Text(outcome.messageFor(l10n) ?? succeeded())),
    );
  }

  String _tierLabel(AppLocalizations l10n, AmsPresetSource source) =>
      switch (source) {
        AmsPresetSource.local => l10n.amsSlotConfigTierLocal,
        AmsPresetSource.cloud => l10n.amsSlotConfigTierCloud,
        AmsPresetSource.builtin => l10n.amsSlotConfigTierBuiltin,
      };
}

/// Colour picker for a slot: the colours this filament is sold in, then the
/// wheel for everything else.
///
/// Pops the chosen colour as six hex digits, or null when cancelled.
///
/// The catalogue is bambuddy's own colour table — the one the spool form picks
/// from — narrowed to the selected preset. It saves hunting a shade on a wheel
/// when the answer is a named colour off a spool, and it makes the slot's colour
/// agree with what the inventory calls the same filament.
class _ColourDialog extends ConsumerStatefulWidget {
  const _ColourDialog({required this.initial, this.presetName});

  /// Six hex digits to open on, or null for white.
  final String? initial;
  final String? presetName;

  @override
  ConsumerState<_ColourDialog> createState() => _ColourDialogState();
}

class _ColourDialogState extends ConsumerState<_ColourDialog> {
  late Color _picked =
      parseSpoolColor(widget.initial) ?? const Color(0xFFFFFFFF);

  /// Catalogue colour currently showing as chosen, or null once the wheel has
  /// been moved off it.
  String? _fromCatalogue;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final preset = widget.presetName;
    final catalogue = preset == null
        ? const <ColorEntry>[]
        : presetColours(
            ref.watch(colorCatalogProvider).valueOrNull ?? const [],
            preset,
          );

    return AlertDialog(
      title: Text(l10n.amsSlotConfigColour),
      contentPadding: const EdgeInsets.symmetric(vertical: 16),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (catalogue.isNotEmpty) ...[
              _label(t, l10n.amsSlotConfigColourCatalogue),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in catalogue)
                      _CatalogueSwatch(
                        entry: entry,
                        selected: _fromCatalogue != null &&
                            sixHexDigits(entry.hexColor) == _fromCatalogue,
                        onTap: () => setState(() {
                          _fromCatalogue = sixHexDigits(entry.hexColor);
                          _picked = parseSpoolColor(entry.hexColor) ?? _picked;
                        }),
                      ),
                  ],
                ),
              ),
              _label(t, l10n.amsSlotConfigColourCustom),
            ],
            ColorPicker(
              pickerColor: _picked,
              onColorChanged: _onWheel,
              // The printer has no use for a transparent filament: a zero alpha
              // is how it reports an *empty* slot, so the picker never offers
              // it.
              enableAlpha: false,
              hexInputBar: true,
              labelTypes: const [],
              portraitOnly: true,
              pickerAreaHeightPercent: 0.7,
            ),
          ],
        ),
      ),
      actions: [
        logTag(
          'ams_slot_colour.cancel',
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
        ),
        logTag(
          'ams_slot_colour.confirm',
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_hexOf(_picked)),
            child: Text(l10n.inventoryColorSelect),
          ),
        ),
      ],
    );
  }

  /// Wheel movement, deliberately without `setState`: rebuilding on every drag
  /// frame would round-trip the colour through the picker's own HSV state and
  /// lose the hue at zero saturation. The one rebuild worth doing is when the
  /// drag leaves the catalogue colour that is showing as chosen, so the tick
  /// does not sit on a swatch the user has moved away from.
  void _onWheel(Color colour) {
    _picked = colour;
    if (_fromCatalogue != null && _hexOf(colour) != _fromCatalogue) {
      setState(() => _fromCatalogue = null);
    }
  }

  Widget _label(DashTokens t, String text) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          text,
          style: t.micro,
        ),
      );
}

/// One catalogue colour, in the same 36pt square the spool form's picker uses.
class _CatalogueSwatch extends StatelessWidget {
  const _CatalogueSwatch({
    required this.entry,
    required this.selected,
    required this.onTap,
  });

  final ColorEntry entry;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final colour = parseSpoolColor(entry.hexColor);
    return Tooltip(
      message: entry.colorName,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: colour,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? t.accentGreen : t.subCardBorder,
              width: selected ? 2 : 1,
            ),
          ),
        ),
      ),
    ).tagged('ams_slot_colour.swatch');
  }
}

/// Six upper-case hex digits for a colour, alpha dropped.
String _hexOf(Color colour) => (colour.toARGB32() & 0xFFFFFF)
    .toRadixString(16)
    .padLeft(6, '0')
    .toUpperCase();

/// Pressure advance the printer falls back to when no profile is selected.
/// Bambu's own default, and what `cali_idx: -1` resolves to.
const _defaultK = 0.02;

/// Value of the K-profile menu's group heading. Never selectable, and no
/// profile can collide with it: a real entry's value is `name|k_value`.
const _otherProfilesHeading = 'heading:other';

/// The catalogue as the sheet renders it, with what the printer filter costs.
typedef _CatalogueView = ({
  List<AmsFilamentPreset> presets,
  int hidden,

  /// Model the filter is keyed on, or null when the printer has not reported
  /// one — in which case there is no filter to offer.
  String? model,
  bool anyPresetAtAll,
  bool cloudNeedsLogin,
});
