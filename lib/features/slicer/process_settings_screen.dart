import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diagnostics/log_tag.dart';
import '../../core/models/process_option.dart';
import '../../core/models/slicer_preset.dart';
import '../../core/slicer/filament_slot_options.dart';
import '../../core/slicer/process_schema_catalog.dart';
import '../../core/slicer/process_settings_codec.dart';
import '../../core/slicer/process_toggle_rules.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../common/dash_input.dart';
import '../common/dash_search_field.dart';
import 'slice_providers.dart';

/// OrcaSlicer's process parameter set, editable before a slice.
///
/// Option labels, tooltips, groups and page names are **English, verbatim** from
/// OrcaSlicer's `PrintConfig.cpp`. That is a deliberate exception to this
/// project's rule that user-visible text goes through [AppLocalizations]: they
/// are 348 upstream strings, they match what Bambu Studio shows on the desktop,
/// and hand-translating them is not viable. The screen's own chrome is localised
/// as usual. See `docs/plans/16-slicer-process-overrides.md` §10.
///
/// Edits are reported upward as they happen rather than returned on pop: the
/// slice sheet below owns the map, so backing out of here keeps them and there
/// is no result to plumb through the navigator.
Future<void> showProcessSettings(
  BuildContext context, {
  required ProcessPresetRef preset,
  required Map<String, Object> values,
  required ValueChanged<Map<String, Object>> onChanged,
  List<FilamentSlotChoice> filamentSlots = const [],
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => ProcessSettingsScreen(
        preset: preset,
        initialValues: values,
        onChanged: onChanged,
        filamentSlots: filamentSlots,
      ),
    ),
  );
}

class ProcessSettingsScreen extends ConsumerStatefulWidget {
  const ProcessSettingsScreen({
    super.key,
    required this.preset,
    required this.initialValues,
    required this.onChanged,
    this.filamentSlots = const [],
  });

  final ProcessPresetRef preset;
  final Map<String, Object> initialValues;
  final ValueChanged<Map<String, Object>> onChanged;

  /// The slots the caller's form offers, in order. Empty leaves the eight
  /// slot-naming options as plain number fields — an STL has no slot list, and
  /// an empty dropdown is worse than the field it would replace.
  final List<FilamentSlotChoice> filamentSlots;

  @override
  ConsumerState<ProcessSettingsScreen> createState() =>
      _ProcessSettingsScreenState();
}

class _ProcessSettingsScreenState extends ConsumerState<ProcessSettingsScreen> {
  late Map<String, Object> _values = {...widget.initialValues};

  /// One per option the user has typed into. Kept for the screen's life because
  /// a controller rebuilt from scratch loses the cursor mid-edit.
  final _controllers = <String, TextEditingController>{};

  OptionMode _mode = OptionMode.simple;
  String? _page;
  String _query = '';

  /// [disabledOptionKeys] runs 152 rules over the whole value map, and only a
  /// value change can move its answer — so it is not re-run for a keystroke in
  /// the search field or a change of page.
  int _revision = 0;
  int? _disabledAt;
  Set<String> _disabled = const {};

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  AppLocalizations get _l10n => AppLocalizations.of(context);

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n;
    final catalog = ref.watch(processSchemaProvider).valueOrNull;
    final presetValues = ref.watch(presetValuesProvider(widget.preset));

    // Both have to be in hand before the first field is drawn: a field seeded
    // from the schema default and reseeded once the sidecar answers would
    // rewrite itself under the user, and resetting a controller's text during a
    // build is not allowed anyway.
    final ready = catalog != null && presetValues.hasValue;

    return Scaffold(
      appBar: dashAppBar(
        context,
        title: l10n.processSettingsTitle,
        actions: [if (ready) _revertAllAction(catalog, presetValues.value)],
      ),
      body: !ready
          ? const Center(child: CircularProgressIndicator())
          : presetValues.value == null
              ? _unavailable(l10n)
              : _body(catalog, presetValues.value!),
    );
  }

  Widget _unavailable(AppLocalizations l10n) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(l10n.processSettingsUnavailable,
              textAlign: TextAlign.center),
        ),
      );

  Widget _revertAllAction(ProcessSchemaCatalog? catalog, PresetValues? values) {
    if (catalog == null || values == null) return const SizedBox.shrink();
    final count = _modifiedCount(catalog, values);
    if (count == 0) return const SizedBox.shrink();
    return TextButton.icon(
      onPressed: () => _revertAll(catalog, values),
      icon: const Icon(Icons.restart_alt, size: 18),
      label: Text(_l10n.processSettingsRevertAll(count)),
    ).tagged('process_settings.revert_all');
  }

  Widget _body(ProcessSchemaCatalog catalog, PresetValues presetValues) {
    final l10n = _l10n;
    final pages = _visiblePages(catalog);
    final active = _activePage(pages);
    final shown = active == null ? pages : [active];
    final disabled = _disabledKeys(catalog);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _modeSelector(),
              const SizedBox(height: 8),
              DashSearchField(
                id: 'process_settings.search',
                hintText: l10n.processSettingsSearchHint,
                onChanged: (value) => setState(() => _query = value),
              ),
              if (!presetValues.resolved) ...[
                const SizedBox(height: 8),
                _defaultsNotice(presetValues),
              ],
            ],
          ),
        ),
        // Hidden while searching: a query cuts across every page, so a page
        // selector would contradict what is on screen.
        if (_query.trim().isEmpty && pages.length > 1)
          _pageSelector(pages, active),
        Expanded(
          child: shown.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(l10n.processSettingsNoMatches,
                        textAlign: TextAlign.center),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    for (final page in shown) ...[
                      // Only worth a heading when several pages are on screen at
                      // once, which only happens while searching.
                      if (shown.length > 1) _pageHeading(page.page),
                      for (final group in page.groups) ...[
                        _groupHeading(group.group),
                        for (final key in group.options)
                          _OptionRow(
                            // Keyed by option: the list's children change as the
                            // mode filter and search narrow it, and without a key
                            // Flutter matches them by position and can pair a row
                            // with the previous occupant's field state.
                            key: ValueKey(key),
                            option: catalog.schema[key]!,
                            controller: _controllerFor(
                                catalog.schema[key]!, presetValues),
                            value: _values[key],
                            presetValue: presetValues.values[key],
                            filamentSlots: widget.filamentSlots,
                            enabled: !disabled.contains(key),
                            onChanged: (value) => _setValue(key, value),
                            onRevert: () => _revert(catalog.schema[key]!,
                                presetValues.values[key]),
                          ),
                      ],
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _modeSelector() {
    final l10n = _l10n;
    // `develop` is upstream's own scratch tier and is never offered.
    const modes = [OptionMode.simple, OptionMode.advanced, OptionMode.expert];
    String label(OptionMode mode) => switch (mode) {
          OptionMode.simple => l10n.processSettingsModeSimple,
          OptionMode.advanced => l10n.processSettingsModeAdvanced,
          OptionMode.expert => l10n.processSettingsModeExpert,
          OptionMode.develop => '',
        };
    return SegmentedButton<OptionMode>(
      segments: [
        for (final mode in modes)
          ButtonSegment(value: mode, label: Text(label(mode))),
      ],
      selected: {_mode},
      showSelectedIcon: false,
      onSelectionChanged: (selection) =>
          setState(() => _mode = selection.first),
    ).tagged('process_settings.mode');
  }

  Widget _pageSelector(List<ProcessPage> pages, ProcessPage? active) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: pages.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final page = pages[i];
          return ChoiceChip(
            // English, from the vendored tree — see the library comment.
            label: Text(page.page),
            selected: active?.page == page.page,
            onSelected: (_) => setState(() => _page = page.page),
          ).tagged('process_settings.page');
        },
      ),
    );
  }

  Widget _pageHeading(String page) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(page.toUpperCase(),
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.primary)),
    );
  }

  Widget _groupHeading(String group) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Text(group, style: theme.textTheme.titleSmall),
    );
  }

  Widget _defaultsNotice(PresetValues presetValues) {
    final l10n = _l10n;
    final theme = Theme.of(context);
    final text = switch (presetValues.cause) {
      PresetValuesCause.sidecarOutdated =>
        l10n.processSettingsDefaultsOutdatedSidecar,
      PresetValuesCause.notConfigured =>
        l10n.processSettingsDefaultsNotConfigured,
      PresetValuesCause.sidecarUnavailable =>
        l10n.processSettingsDefaultsSidecarUnavailable,
      _ => l10n.processSettingsDefaultsUnavailable,
    };
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline,
              size: 18, color: theme.colorScheme.onSecondaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer)),
          ),
        ],
      ),
    );
  }

  // --- state ---

  void _setValue(String key, Object? value) {
    setState(() {
      // Replaced rather than mutated so the disabled-set cache below can tell
      // that the answer may have moved.
      final next = {..._values};
      if (value == null) {
        next.remove(key);
      } else {
        next[key] = value;
      }
      _values = next;
      _revision++;
    });
    widget.onChanged(_values);
  }

  void _revert(ProcessOption option, Object? presetValue) {
    _controllers[option.key]?.text = baselineForDisplay(option, presetValue);
    _setValue(option.key, null);
  }

  void _revertAll(ProcessSchemaCatalog catalog, PresetValues presetValues) {
    for (final entry in _controllers.entries) {
      final option = catalog.schema[entry.key];
      if (option == null) continue;
      entry.value.text =
          baselineForDisplay(option, presetValues.values[entry.key]);
    }
    setState(() {
      _values = {};
      _revision++;
    });
    widget.onChanged(_values);
  }

  int _modifiedCount(ProcessSchemaCatalog catalog, PresetValues presetValues) {
    var count = 0;
    for (final entry in _values.entries) {
      final option = catalog.schema[entry.key];
      if (option == null) continue;
      if (isModified(option, entry.value, presetValues.values[entry.key])) {
        count++;
      }
    }
    return count;
  }

  Set<String> _disabledKeys(ProcessSchemaCatalog catalog) {
    if (_disabledAt != _revision) {
      _disabled = disabledOptionKeys(
        values: _values,
        schema: catalog.schema,
        toggles: catalog.toggles,
      );
      _disabledAt = _revision;
    }
    return _disabled;
  }

  /// A text controller per option, seeded once from what this slice would use.
  TextEditingController _controllerFor(
    ProcessOption option,
    PresetValues presetValues,
  ) {
    return _controllers[option.key] ??= TextEditingController(
      text: _values[option.key]?.toString() ??
          baselineForDisplay(option, presetValues.values[option.key]),
    );
  }

  // --- filtering ---

  /// Underscores and spaces are interchangeable, so "outer wall speed" finds
  /// `outer_wall_speed`. That matters: several labels only make sense with their
  /// group ("Outer wall" under Speed), so the key is often the only place the
  /// whole phrase appears.
  static final _separators = RegExp(r'[_\s]+');
  String _searchable(String text) =>
      text.toLowerCase().replaceAll(_separators, ' ').trim();

  List<ProcessPage> _visiblePages(ProcessSchemaCatalog catalog) {
    final needle = _searchable(_query);

    bool visible(String key, String group, String page) {
      final option = catalog.schema[key];
      // A tree key the schema does not declare has no control to draw.
      if (option == null || !option.mode.visibleAt(_mode)) return false;
      if (needle.isEmpty) return true;
      // Group and page are matched too, so "speed" lists the Speed page rather
      // than only the handful of options with "speed" in the label.
      for (final field in [
        key,
        option.label,
        option.tooltip ?? '',
        group,
        page,
      ]) {
        if (_searchable(field).contains(needle)) return true;
      }
      return false;
    }

    final out = <ProcessPage>[];
    for (final page in catalog.tree) {
      final groups = <ProcessGroup>[];
      for (final group in page.groups) {
        final options = [
          for (final key in group.options)
            if (visible(key, group.group, page.page)) key,
        ];
        if (options.isNotEmpty) {
          groups.add(ProcessGroup(group: group.group, options: options));
        }
      }
      if (groups.isNotEmpty) {
        out.add(ProcessPage(page: page.page, icon: page.icon, groups: groups));
      }
    }
    return out;
  }

  /// The page to show on its own, or null while searching — a query spans every
  /// page, so all matches are listed.
  ProcessPage? _activePage(List<ProcessPage> pages) {
    if (pages.isEmpty || _query.trim().isNotEmpty) return null;
    return pages.firstWhere((p) => p.page == _page, orElse: () => pages.first);
  }
}

/// One option: its label, the control for its type, and the markers saying
/// whether it differs from the preset.
class _OptionRow extends StatelessWidget {
  const _OptionRow({
    super.key,
    required this.option,
    required this.controller,
    required this.value,
    required this.presetValue,
    required this.filamentSlots,
    required this.enabled,
    required this.onChanged,
    required this.onRevert,
  });

  final ProcessOption option;
  final TextEditingController controller;
  final Object? value;
  final Object? presetValue;

  /// The caller's filament slots, for the eight options whose value names one.
  final List<FilamentSlotChoice> filamentSlots;

  /// False when the slicer's own rules say this setting does nothing right now.
  /// The row stays visible: a missing row reads as a missing feature, and the
  /// rules fail open, so a wrong grey-out is the mistake to avoid making loud.
  final bool enabled;

  final ValueChanged<Object?> onChanged;
  final VoidCallback onRevert;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final modified = isModified(option, value, presetValue);

    final label = Row(
      children: [
        Expanded(
          child: Text(
            option.label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: enabled
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
        if (modified)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Icon(Icons.circle, size: 8, color: theme.colorScheme.primary),
          ),
        SizedBox(
          width: 36,
          child: modified
              ? IconButton(
                  icon: const Icon(Icons.undo, size: 18),
                  visualDensity: VisualDensity.compact,
                  tooltip: l10n.processSettingsRevert,
                  onPressed: onRevert,
                ).tagged('process_settings.revert')
              : null,
        ),
      ],
    );

    // The tooltip is the only place 347 upstream descriptions can go on a phone;
    // a long press is how they are reached.
    return Tooltip(
      message: option.tooltip ?? '',
      triggerMode: TooltipTriggerMode.longPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: option.type == OptionType.coBool
            ? Row(children: [
                Expanded(child: label),
                Switch(
                  value: _asBool(),
                  onChanged: enabled ? (v) => onChanged(v) : null,
                ).tagged('process_settings.option_bool'),
              ])
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  label,
                  const SizedBox(height: 4),
                  _control(context, l10n),
                ],
              ),
      ),
    );
  }

  bool _asBool() {
    final current = value ?? presetValue ?? option.defaultValue;
    if (current is bool) return current;
    return current == '1' || current == 'true' || current == 1;
  }

  Widget _control(BuildContext context, AppLocalizations l10n) {
    // Before the type branches, as on the server panel: the value *is* an int,
    // but a spinner over "1, 2, 3" leaves the user mapping slot numbers to their
    // own filaments by hand.
    if (filamentSlots.isNotEmpty && namesFilamentSlot(option)) {
      return _filamentSlotControl(context, l10n);
    }
    if (option.type == OptionType.coEnum && option.enumValues != null) {
      return _enumControl(context);
    }
    return _textControl(context, l10n);
  }

  /// Slot picker for the eight options that store a filament slot index.
  ///
  /// Values stay strings, exactly as the number field it replaces emits them, so
  /// nothing downstream can tell which control produced an edit.
  Widget _filamentSlotControl(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final current = value?.toString() ?? baselineForDisplay(option, presetValue);
    final offered = ['0', for (final slot in filamentSlots) '${slot.slot}'];

    // A preset (or the source file) can name a slot this file does not have. It
    // is shown as its own entry rather than left unselected: a blank control
    // would hide the one value worth seeing. An empty value is not one of those
    // — it is malformed, and a slot named "" would be an invention.
    final missing =
        current.isEmpty || offered.contains(current) ? null : current;

    String slotLabel(FilamentSlotChoice slot) {
      final text = l10n.processSettingsFilamentSlot('${slot.slot}', slot.label);
      return slot.unused ? '$text · ${l10n.sliceFilamentUnused}' : text;
    }

    DropdownMenuEntry<String> entry(String value, String label,
            {bool dim = false}) =>
        DropdownMenuEntry(
          value: value,
          label: label,
          // A DropdownMenuEntry cannot be wrapped, so the tag rides on the label
          // widget — as in [_enumControl]. Ellipsised because preset names run
          // well past the field's width.
          labelWidget: logTag(
            'process_settings.option_filament_value',
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: dim
                  ? TextStyle(color: theme.colorScheme.onSurfaceVariant)
                  : null,
            ),
          ),
        );

    return dashCombo<String>(
      context,
      id: 'process_settings.option_filament',
      // Keyed by the selection for the reason spelled out in [_enumControl].
      fieldKey: ValueKey(current),
      initialSelection: current,
      enabled: enabled,
      onSelected: (selected) => onChanged(selected),
      entries: [
        entry('0', l10n.processSettingsFilamentDefault),
        for (final slot in filamentSlots)
          entry('${slot.slot}', slotLabel(slot), dim: slot.unused),
        if (missing != null)
          entry(missing, l10n.processSettingsFilamentSlotMissing(missing),
              dim: true),
      ],
    );
  }

  /// M3 [DropdownMenu] rather than `DropdownButtonFormField`: the latter uses the
  /// old overlay and does not scroll sanely with 26 entries.
  Widget _enumControl(BuildContext context) {
    final values = option.enumValues!;
    final labels = option.enumLabels;
    final current = value?.toString() ??
        baselineForDisplay(option, presetValue);
    final selectable = values.contains(current);
    return dashCombo<String>(
      context,
      id: 'process_settings.option_enum',
      // Keyed by the selection so `initialSelection` always takes effect.
      // `DropdownMenu` re-applies it on update only when the value matches an
      // entry, so a preset holding a value the vendored schema does not declare
      // would keep displaying the last pick after a revert — showing a setting
      // the slice is not going to use.
      fieldKey: ValueKey(selectable ? current : null),
      initialSelection: selectable ? current : null,
      enabled: enabled,
      onSelected: (selected) => onChanged(selected),
      entries: [
        for (var i = 0; i < values.length; i++)
          if ((labels != null && i < labels.length) ? labels[i] : values[i]
              case final text)
            DropdownMenuEntry(
              value: values[i],
              // Upstream labels where they exist, the wire value otherwise.
              label: text,
              // A DropdownMenuEntry cannot be wrapped, so the tag rides on the
              // label widget. One id for every entry: which value was picked is
              // never part of an id.
              labelWidget:
                  logTag('process_settings.option_enum_value', Text(text)),
            ),
      ],
    );
  }

  Widget _textControl(BuildContext context, AppLocalizations l10n) {
    final numeric = switch (option.type) {
      OptionType.coInt || OptionType.coFloat || OptionType.coPercent => true,
      _ => false,
    };
    final min = numericBound(option.min);
    final max = numericBound(option.max);
    final unit = displaySidetext(option);
    final outOfRange = numeric && _outOfRange(min, max);

    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: numeric
          ? TextInputType.numberWithOptions(
              decimal: option.type != OptionType.coInt,
              signed: (min ?? 0) < 0,
            )
          : TextInputType.text,
      decoration: InputDecoration(
        isDense: true,
        suffixText: unit,
        // Only when it is actually wrong: bounds on all 348 rows would be noise,
        // and some are unresolved expressions with no bound to state.
        errorText: outOfRange
            ? l10n.processSettingsOutOfRange(_rangeLabel(min, max))
            : null,
        helperText: enabled ? null : l10n.processSettingsDisabledHint,
      ),
      onChanged: (text) => onChanged(text),
    ).tagged(numeric
        ? 'process_settings.option_number'
        : 'process_settings.option_text');
  }

  bool _outOfRange(double? min, double? max) {
    final typed = numericBound(value?.toString());
    if (typed == null) return false;
    return (min != null && typed < min) || (max != null && typed > max);
  }

  String _rangeLabel(double? min, double? max) {
    String show(double v) => v == v.roundToDouble() && v.abs() < 1e15
        ? v.toInt().toString()
        : v.toString();
    if (min != null && max != null) return '${show(min)} – ${show(max)}';
    if (min != null) return '≥ ${show(min)}';
    return '≤ ${show(max!)}';
  }
}
