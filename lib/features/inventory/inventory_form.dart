part of 'inventory_screen.dart';

/// Spool create/edit sheet. Text fields + validation; save via [inventoryProvider]
/// (create if [existing] == null, else update). Empty numeric fields → null
/// (server uses defaults). Color previewed live.
class _SpoolFormSheet extends ConsumerStatefulWidget {
  const _SpoolFormSheet({this.existing});

  final Spool? existing;

  @override
  ConsumerState<_SpoolFormSheet> createState() => _SpoolFormSheetState();
}

/// Fixed filament effects for dropdown (None + popular).
const _effectOptions = [
  'Silk',
  'Matte',
  'Glow',
  'Sparkle',
  'Marble',
  'Metal',
  'Dual',
  'Gradient',
];

class _SpoolFormSheetState extends ConsumerState<_SpoolFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _c;
  int? _coreWeightCatalogId;
  String? _effectType;

  /// Selected slicer filament preset: `slicer_filament` code + human name.
  /// The print profile the spool is added with (bambuddy "Slicer Preset").
  String? _slicerFilament;
  String? _slicerFilamentName;

  /// Per-printer-model preset overrides as they will be written, keyed by
  /// [SpoolPresetOverride.key].
  ///
  /// Null until the server's rows have arrived, and null is also "do not
  /// write": the route replaces the whole list, so saving from a failed read
  /// would delete overrides the user never saw. [_overridesDirty] is the other
  /// half of that — an untouched section writes nothing at all.
  Map<String, SpoolPresetOverride>? _overrides;
  bool _overridesDirty = false;

  /// The spool this sheet created, once it has created one.
  ///
  /// Saving is two writes — the spool, then its per-model presets — and the
  /// second one failing leaves the sheet open so the picks are not lost. That
  /// retry must not mint a second spool: from here on the form is editing the
  /// one it just made, even though [widget.existing] is still null.
  int? _createdSpoolId;

  String _colorQuery = '';
  bool _materialMissing = false;
  bool _saving = false;

  /// How many identical spools to create at once ("restock"). Create mode only;
  /// server caps the bulk endpoint at 100.
  int _quantity = 1;
  static const _maxQuantity = 100;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final s = widget.existing;
    String n(num? v) => v == null ? '' : v.toString();
    // Remaining weight = label − used. For new spool, default full 1000 g.
    final remaining = s == null ? '1000' : n(s.remainingWeight.round());
    _c = {
      'material': TextEditingController(text: s?.material ?? ''),
      'brand': TextEditingController(text: s?.brand ?? ''),
      'subtype': TextEditingController(text: s?.subtype ?? ''),
      'colorName': TextEditingController(text: s?.colorName ?? ''),
      'rgba': TextEditingController(text: s?.rgba ?? ''),
      'extraColors': TextEditingController(text: s?.extraColors ?? ''),
      'labelWeight': TextEditingController(
        text: s == null ? '1000' : n(s.labelWeight),
      ),
      'remaining': TextEditingController(text: remaining),
      'measured': TextEditingController(text: n(s?.lastScaleWeight)),
      'coreWeight': TextEditingController(text: n(s?.coreWeight ?? 250)),
      'costPerKg': TextEditingController(text: n(s?.costPerKg)),
      'category': TextEditingController(text: s?.category ?? ''),
      'lowStock': TextEditingController(text: n(s?.lowStockThresholdPct)),
      'location': TextEditingController(text: s?.storageLocation ?? ''),
      'note': TextEditingController(text: s?.note ?? ''),
    };
    _coreWeightCatalogId = s?.coreWeightCatalogId;
    _effectType = s?.effectType;
    _slicerFilament = s?.slicerFilament;
    _slicerFilamentName = s?.slicerFilamentName;
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  String? _trim(String key) => _trimmedField(_c, key);

  int? _parseIntField(String key) => _intField(_c, key);

  /// Measured weight is gross (filament + empty spool/core). After entering scale
  /// reading, calculate remaining filament: remaining = measured − empty spool weight.
  /// This ensures save (weight_used = label − remaining) actually changes spool state —
  /// without it, the reading alone wouldn't update anything.
  void _applyScaleWeight(String raw) {
    final measured = parseUserDecimal(raw);
    if (measured == null) return;
    final core = parseUserDecimal(_c['coreWeight']!.text) ?? 0;
    final remaining = (measured - core).clamp(0, double.infinity);
    // No setState needed: the bound TextFormField already rebuilds itself
    // from its controller's own listener when `.text` changes programmatically.
    _c['remaining']!.text = remaining.round().toString();
  }

  /// Sets color from database (hex + name + optional gradient/effect).
  void _applyColor(ColorEntry e) {
    setState(() {
      _c['rgba']!.text = e.hexColor;
      _c['colorName']!.text = e.colorName;
      _c['extraColors']!.text = e.extraColors ?? '';
      _effectType = e.effectType;
    });
  }

  Future<void> _save() async {
    final material = _c['material']!.text.trim();
    final formOk = _formKey.currentState!.validate();
    if (material.isEmpty) {
      setState(() => _materialMissing = true);
    }
    if (!formOk || material.isEmpty) return;

    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    // Server requires low-stock threshold in range 1..99 (outside = 422).
    final lowStock = _parseIntField('lowStock')?.clamp(1, 99);
    final label = _parseIntField('labelWeight');
    final remaining = parseUserDecimal(_c['remaining']!.text);
    // Remaining weight controls usage: weight_used = label − remaining.
    double? used;
    if (remaining != null && label != null) {
      used = (label - remaining).clamp(0, label).toDouble();
    } else if (_isEdit && remaining == null) {
      used = widget.existing!.weightUsed;
    }
    final draft = SpoolDraft(
      material: material,
      brand: _trim('brand'),
      subtype: _trim('subtype'),
      colorName: _trim('colorName'),
      rgba: normalizeRgba(_c['rgba']!.text),
      extraColors: _trim('extraColors'),
      effectType: _effectType,
      labelWeight: label,
      weightUsed: used,
      coreWeight: _parseIntField('coreWeight'),
      coreWeightCatalogId: _coreWeightCatalogId,
      lastScaleWeight: _parseIntField('measured'),
      costPerKg: parseUserDecimal(_c['costPerKg']!.text),
      category: _trim('category'),
      lowStockThresholdPct: lowStock,
      storageLocation: _trim('location'),
      slicerFilament: _slicerFilament,
      slicerFilamentName: _slicerFilamentName,
      note: _trim('note'),
    );
    setState(() => _saving = true);
    final notifier = ref.read(inventoryProvider.notifier);
    // Read before the first await: a WidgetRef is not usable once the sheet it
    // belongs to is gone, and the spool write is what closes it.
    final repo = ref.read(inventoryRepositoryProvider);
    try {
      final String message;
      // Which spool the per-model presets belong to. Null for a restock, which
      // creates several and names none of them.
      final int? spoolId;
      if (_isEdit) {
        await notifier.updateSpool(widget.existing!.id, draft);
        spoolId = widget.existing!.id;
        message = l10n.inventorySpoolUpdated;
      } else if (_createdSpoolId case final id?) {
        // A retry after the presets failed: the spool exists, so this is the
        // PATCH the edit path would send, not another create.
        await notifier.updateSpool(id, draft);
        spoolId = id;
        message = l10n.inventorySpoolCreated;
      } else if (_quantity > 1) {
        final created = await notifier.bulkCreateSpools(draft, _quantity);
        spoolId = null;
        message = l10n.inventorySpoolsCreated(created);
      } else {
        final created = await notifier.createSpool(draft);
        _createdSpoolId = created?.id;
        spoolId = created?.id;
        message = l10n.inventorySpoolCreated;
      }
      if (!await _savePresetOverrides(repo, spoolId, l10n, messenger)) return;
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.snack(message);
    } on AppApiException catch (e) {
      if (mounted) setState(() => _saving = false);
      showApiFailure(mounted ? messenger : null, e, l10n,
          action: 'spool_form.save');
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.snack(l10n.inventorySaveFailed);
    }
  }

  /// Writes the per-model preset overrides for the spool just saved, and says
  /// whether the form may close.
  ///
  /// Nothing is sent unless the section was both read and touched: the route
  /// replaces the whole list, so a blind write is a delete. A failure here
  /// leaves the sheet open with the picks still in it — the spool itself is
  /// already saved, and the retry costs one PATCH of a spool that now exists
  /// either way (see [_createdSpoolId]).
  Future<bool> _savePresetOverrides(
    InventoryRepository repo,
    int? spoolId,
    AppLocalizations l10n,
    ScaffoldMessengerState messenger,
  ) async {
    final overrides = _overrides;
    if (spoolId == null || overrides == null || !_overridesDirty) return true;
    try {
      await repo.savePresetOverrides(spoolId, overrides.values.toList());
      _overridesDirty = false;
      return true;
    } on AppApiException catch (e) {
      if (mounted) setState(() => _saving = false);
      showApiFailure(mounted ? messenger : null, e, l10n,
          action: 'spool_form.save_model_presets');
      return false;
    } on Object {
      if (mounted) setState(() => _saving = false);
      messenger.snack(l10n.inventoryPrinterPresetsSaveFailed);
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final materials = ref.watch(materialOptionsProvider);
    final brands = ref.watch(brandOptionsProvider);
    final subtypes = ref.watch(subtypeOptionsProvider);
    final locations = ref.watch(locationOptionsProvider);
    final cores = ref.watch(coreWeightsProvider).valueOrNull ?? const [];
    // Per-model presets: only asked for on a server that has the routes, and
    // only for a spool that exists — a new one has no rows to read.
    final overridesSupported =
        ref.watch(presetOverridesSupportedProvider).orFalse;
    final showOverrides = _showsPresetOverrides(overridesSupported);
    final stored = showOverrides && _isEdit
        ? ref.watch(spoolPresetOverridesProvider(widget.existing!.id))
        : const AsyncValue<List<SpoolPresetOverride>>.data([]);
    if (showOverrides) {
      final rows = stored.valueOrNull;
      if (rows != null) _seedOverrides(rows);
    }
    final models = showOverrides
        ? ref.watch(printerModelsProvider).valueOrNull ?? const <String>[]
        : const <String>[];

    return DraggableSheetSurface(
      initialSize: 0.9,
      minSize: 0.5,
      builder: (context, controller) => Form(
        key: _formKey,
        child: ListView(
          controller: controller,
          padding: EdgeInsets.fromLTRB(16, 0, 16, 24 + bottomInset),
          children: [
            Row(
              children: [
                ValueListenableBuilder(
                  valueListenable: _c['rgba']!,
                  builder: (context, _, _) =>
                      SpoolSwatch(rgba: _c['rgba']!.text, size: 40, radius: 12),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _isEdit ? l10n.inventoryEditSpool : l10n.inventoryNewSpool,
                    style: t.display,
                  ),
                ),
                // Bulk "restock": how many identical spools to create. Header
                // placement (create mode only) so it reads before the fields.
                if (!_isEdit) ...[
                  const SizedBox(width: 8),
                  _quantityStepper(l10n),
                ],
              ],
            ),
            const SizedBox(height: 12),

            // --- FILAMENT ---
            _FormSection(label: l10n.inventorySectionFilament),
            _slicerPresetField(l10n),
            _combo(
              'material',
              l10n.inventoryFieldMaterial,
              materials,
              required: true,
              errorText: _materialMissing ? l10n.inventoryFieldRequired : null,
            ),
            _combo('brand', l10n.inventoryFieldBrand, brands),
            _combo('subtype', l10n.inventoryFieldSubtype, subtypes),
            _field('labelWeight', l10n.inventoryFieldLabelWeight, number: true),

            const SizedBox(height: 8),

            // --- COLOR ---
            _FormSection(label: l10n.inventorySectionColor),
            ValueListenableBuilder(
              valueListenable: _c['rgba']!,
              builder: (context, _, _) => _ColorPicker(
                rgba: _c['rgba']!.text,
                query: _colorQuery,
                onQuery: (v) => setState(() => _colorQuery = v),
                onPick: _applyColor,
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: _field('colorName', l10n.inventoryFieldColorName),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ValueListenableBuilder(
                    valueListenable: _c['rgba']!,
                    builder: (context, _, _) => _hexColorPickerField(l10n),
                  ),
                ),
              ],
            ),
            _field(
              'extraColors',
              l10n.inventoryFieldExtraColors,
              hint: l10n.inventoryExtraColorsHint,
            ),
            _effectDropdown(l10n),

            const SizedBox(height: 8),

            // --- ADDITIONAL ---
            _FormSection(label: l10n.inventorySectionAdditional),
            _emptySpoolField(l10n, cores),
            ValueListenableBuilder(
              valueListenable: _c['labelWeight']!,
              builder: (context, _, _) {
                final labelInt = parseUserRoundedInt(_c['labelWeight']!.text);
                return _field(
                  'remaining',
                  l10n.inventoryFieldRemainingWeight,
                  number: true,
                  suffixText: labelInt != null
                      ? l10n.inventoryRemainingOfLabel(labelInt)
                      : null,
                );
              },
            ),
            _field(
              'measured',
              l10n.inventoryFieldMeasuredWeight,
              number: true,
              onChanged: _applyScaleWeight,
            ),
            _field('costPerKg', l10n.inventoryFieldCostPerKg, number: true),
            _field('category', l10n.inventoryFieldCategory),
            _field(
              'lowStock',
              l10n.inventoryFieldLowStock,
              number: true,
              hint: l10n.inventoryLowStockHint,
            ),
            _combo('location', l10n.inventoryFieldLocation, locations),
            _field('note', l10n.inventoryFieldNote, maxLines: 3),

            if (showOverrides)
              ..._presetOverridesSection(l10n, stored, models),

            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: t.accentGreen,
                  foregroundColor: _onAccentGreen,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                onPressed: _saving ? null : _save,
                child: _saving
                    ? DashSpinner(size: 20, color: _onAccentGreen)
                    : Text(
                        !_isEdit && _quantity > 1
                            ? l10n.inventoryAddSpools(_quantity)
                            : l10n.inventorySave,
                        style: const TextStyle(
                          fontFamily: DashTokens.fontUi,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ).tagged('spool_form.save'),
            ),
          ],
        ),
      ),
    );
  }

  /// Editable combo (dropdown with filtering + custom entry) for material/brand/variant.
  /// Value held by controller — entry outside list is kept.
  Widget _combo(
    String key,
    String label,
    List<String> options, {
    bool required = false,
    String? errorText,
  }) {
    final t = DashTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: dashCombo<String>(
        context,
        id: _fieldTag(key),
        controller: _c[key],
        label: Text(required ? '$label *' : label),
        errorText: errorText,
        filterable: true,
        textStyle: t.body,
        onSelected: (v) {
          if (required && v != null && v.isNotEmpty) {
            setState(() => _materialMissing = false);
          }
        },
        entries: [
          // `logTagMaterial` keeps the pick out of the identifier: on the
          // material combo it rides in `mat`, and a brand or variant is not a
          // known material, so it falls back to the bare id.
          for (final o in options)
            DropdownMenuEntry(
              value: o,
              label: o,
              labelWidget:
                  logTagMaterial('${_fieldTag(key)}.option', o, Text(o)),
            ),
        ],
      ),
    );
  }


  /// Empty Spool Weight field: a searchable picker from the core catalog (sets
  /// weight + id) beside an editable weight in grams. If catalog empty — weight
  /// only.
  Widget _emptySpoolField(AppLocalizations l10n, List<CoreWeightEntry> cores) {
    final t = DashTokens.of(context);
    final weightField = SizedBox(
      width: cores.isEmpty ? null : 110,
      child: TextFormField(
        controller: _c['coreWeight'],
        style: t.body,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: dashDecoration(t, labelText: 'g'),
        onChanged: (_) => setState(() => _coreWeightCatalogId = null),
      ).tagged('spool_form.core_weight_value'),
    );
    if (cores.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: l10n.inventoryFieldEmptySpoolWeight,
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
          child: weightField,
        ),
      );
    }
    // Catalog entry referenced by an edited spool may have been removed
    // server-side since — drop the dangling id so the field shows the typed
    // weight as a manual value rather than a stale name.
    if (_coreWeightCatalogId != null &&
        !cores.any((c) => c.id == _coreWeightCatalogId)) {
      _coreWeightCatalogId = null;
    }
    final selected =
        cores.where((c) => c.id == _coreWeightCatalogId).firstOrNull;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: dashPickerField(
              context,
              id: 'spool_form.core_weight',
              label: l10n.inventoryFieldEmptySpoolWeight,
              placeholder: l10n.inventoryCoreWeightSelect,
              value: selected?.name,
              onTap: () => _openCoreWeightPicker(l10n),
              // The row this sits in carries the field spacing already.
              padding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(width: 8),
          weightField,
        ],
      ),
    );
  }

  /// Opens the searchable empty-spool (core weight) picker; on selection stores
  /// the catalog id and fills the weight box from the chosen entry.
  Future<void> _openCoreWeightPicker(AppLocalizations l10n) async {
    final picked = await dashSurfaceSheet<CoreWeightEntry>(
      context,
      builder: (_) => const _CoreWeightPicker(),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _coreWeightCatalogId = picked.id;
      _c['coreWeight']!.text = picked.weight.toString();
    });
  }

  Widget _effectDropdown(AppLocalizations l10n) {
    final t = DashTokens.of(context);
    final options = <String>{..._effectOptions, ?_effectType};
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: DropdownButtonFormField<String?>(
        initialValue: _effectType,
        isExpanded: true,
        style: t.body,
        dropdownColor: t.isDark ? const Color(0xFF141A13) : Colors.white,
        decoration: dashDecoration(t, labelText: l10n.inventoryFieldEffect),
        items: [
          DropdownMenuItem(
            value: null,
            child: logTag('${_fieldTag('effect')}.none',
                Text(l10n.inventoryEffectNone)),
          ),
          for (final e in options)
            DropdownMenuItem(
              value: e,
              child: logTag('${_fieldTag('effect')}.option', Text(e)),
            ),
        ],
        onChanged: (v) => setState(() => _effectType = v),
      ).tagged(_fieldTag('effect')),
    );
  }

  /// Compact quantity stepper for bulk "restock", sized to sit in the sheet
  /// header (− [n] +). Clamped to 1..[_maxQuantity]; a tooltip explains it
  /// creates N identical spools.
  Widget _quantityStepper(AppLocalizations l10n) {
    final t = DashTokens.of(context);
    void setQty(int v) => setState(() => _quantity = v.clamp(1, _maxQuantity));
    Widget btn(IconData icon, VoidCallback? onTap) => IconButton(
          onPressed: onTap,
          icon: Icon(icon, color: t.textSecondary),
          iconSize: 20,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(width: 36, height: 36),
          padding: EdgeInsets.zero,
        ).tagged('spool_form.quantity_step');
    return Tooltip(
      message: l10n.inventoryQuantityHint,
      child: Container(
        decoration: BoxDecoration(
          color: t.subCard,
          border: Border.all(color: t.subCardBorder),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            btn(Icons.remove, _quantity > 1 ? () => setQty(_quantity - 1) : null),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 24),
              child: Text(
                '$_quantity',
                textAlign: TextAlign.center,
                style: t.monoTitle,
              ),
            ),
            btn(
              Icons.add,
              _quantity < _maxQuantity ? () => setQty(_quantity + 1) : null,
            ),
          ],
        ),
      ),
    );
  }

  /// Slicer preset field: the print profile the spool is added with
  /// (`slicer_filament`). Tapping opens a searchable picker; the current
  /// selection (or "None") shows inline, with a clear button once set.
  Widget _slicerPresetField(AppLocalizations l10n) {
    final selected = _slicerFilamentName ?? _slicerFilament;
    return dashPickerField(
      context,
      id: 'spool_form.preset',
      label: l10n.inventoryFieldSlicerPreset,
      helperText: l10n.inventorySlicerPresetHint,
      placeholder: l10n.inventorySlicerPresetNone,
      value: selected,
      prefixIcon: Icons.tune,
      onTap: () => _openSlicerPresetPicker(l10n),
      clear: (
        id: 'spool_form.preset.clear',
        onPressed: () => setState(() {
          _slicerFilament = null;
          _slicerFilamentName = null;
        }),
      ),
    );
  }

  /// Opens the preset picker; on selection stores id+name and, when material is
  /// still blank, seeds it from the preset's filament type (cheap auto-fill).
  Future<void> _openSlicerPresetPicker(AppLocalizations l10n) async {
    final picked = await dashSurfaceSheet<SlicerPreset>(
      context,
      builder: (_) => _SlicerPresetPicker(material: _c['material']!.text),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _slicerFilament = picked.id;
      _slicerFilamentName = picked.name;
      final mat = picked.filamentType?.trim();
      if (_c['material']!.text.trim().isEmpty && mat != null && mat.isNotEmpty) {
        _c['material']!.text = mat;
        _materialMissing = false;
      }
    });
  }

  /// Whether the per-model preset section is offered: the server has to have
  /// the routes, and a bulk "restock" has no spool to write them to —
  /// `bulkCreateSpools` answers with a count, not with the rows it created.
  bool _showsPresetOverrides(bool supported) =>
      supported && (_isEdit || _quantity == 1);

  /// Takes the editable copy from what the server holds, once.
  ///
  /// Assigned during build rather than from a listener: [rows] arrived with the
  /// watch that scheduled this build, so the frame already reflects them and a
  /// `setState` here would only ask for the same one again.
  void _seedOverrides(List<SpoolPresetOverride> rows) {
    _overrides ??= {for (final row in rows) row.key: row};
  }

  /// The rows the section offers: one per printer model in the fleet, plus any
  /// stored override the fleet does not account for — a model that is no longer
  /// there, and the per-nozzle rows the web spool form writes, which the app
  /// shows and carries through rather than silently replacing with its own
  /// whole-model row.
  List<SpoolPresetOverride> _overrideRows(List<String> models) {
    final fleet = [
      for (final model in models) SpoolPresetOverride(printerModel: model),
    ];
    final known = {for (final row in fleet) row.key};
    final stored = [
      for (final row in _overrides?.values ?? const <SpoolPresetOverride>[])
        if (!known.contains(row.key)) row,
    ]..sort((a, b) => a.key.compareTo(b.key));
    return [...fleet, ...stored];
  }

  /// Which slicer preset this spool uses on one printer model, when that is not
  /// the single preset it carries for the whole fleet.
  ///
  /// A read that failed leaves the rows out entirely and says so: the route
  /// replaces the whole list, so offering an edit on top of rows nobody could
  /// read is offering to delete them.
  List<Widget> _presetOverridesSection(
    AppLocalizations l10n,
    AsyncValue<List<SpoolPresetOverride>> stored,
    List<String> models,
  ) {
    final loadFailed = stored.hasError;
    // Nothing is editable until the stored rows are in hand, and not only
    // because a row would claim the spool's own preset applies when it may
    // not: a pick made first would seed the map by itself, the rows arriving
    // after would find it already seeded, and the save would replace the whole
    // list with that one pick.
    final loading = _overrides == null && !loadFailed;
    final rows = _overrideRows(models);
    if (rows.isEmpty && !loadFailed && !loading) return const [];
    return [
      const SizedBox(height: 8),
      _FormSection(label: l10n.inventorySectionPrinterPresets),
      InlineNote(
        l10n.inventoryPrinterPresetsHint,
        icon: Icons.info_outline,
        padding: const EdgeInsets.only(bottom: 2),
      ),
      if (loadFailed)
        InlineNote(l10n.inventoryPrinterPresetsLoadFailed, urgent: true)
      else if (loading)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: DashLoading(),
        )
      else
        for (final row in rows) _presetOverrideField(l10n, row),
    ];
  }

  /// One model's row. Same chrome as [_slicerPresetField], which is the field
  /// it overrides — the model is the label, the preset is the value.
  Widget _presetOverrideField(AppLocalizations l10n, SpoolPresetOverride row) {
    final current = _overrides?[row.key];
    final chosen = current?.slicerFilamentName ?? current?.slicerFilament;
    return dashPickerField(
      context,
      id: 'spool_form.model_preset',
      label: row.nozzleDiameter.isEmpty
          ? row.printerModel
          : l10n.inventoryPrinterPresetNozzle(
              row.printerModel,
              row.nozzleDiameter,
            ),
      // No row at all is the placeholder: the spool's own preset applies. A row
      // that carries no preset is a different answer — "use none here", which
      // the server honours instead of falling back — so it is a value.
      placeholder: l10n.inventoryPrinterPresetDefault,
      value: current == null
          ? null
          : chosen ?? l10n.inventorySlicerPresetNone,
      prefixIcon: Icons.print_outlined,
      onTap: () => _pickOverridePreset(l10n, row),
      clear: (
        id: 'spool_form.model_preset.clear',
        onPressed: () => setState(() {
          _overrides?.remove(row.key);
          _overridesDirty = true;
        }),
      ),
    );
  }

  /// Picks the preset for one model. The app writes the whole-model level
  /// (`nozzle_diameter: ""`), which the route documents for a client that wants
  /// one value to cover a model; a row that already names a nozzle keeps it.
  Future<void> _pickOverridePreset(
    AppLocalizations l10n,
    SpoolPresetOverride row,
  ) async {
    final picked = await dashSurfaceSheet<SlicerPreset>(
      context,
      builder: (_) => _SlicerPresetPicker(
        printerModel: row.printerModel,
        material: _c['material']!.text,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      (_overrides ??= {})[row.key] = row.withPreset(picked.id, picked.name);
      _overridesDirty = true;
    });
  }

  /// Color field: instead of manual hex entry, opens color picker (HSV wheel + hex bar).
  /// On selection, writes hex `RRGGBBAA` to `rgba` controller (alpha preserved
  /// from previous value, default `FF`).
  Widget _hexColorPickerField(AppLocalizations l10n) {
    final t = DashTokens.of(context);
    final hex = _c['rgba']!.text.trim();
    // Unparseable reads as unset, which is what it looks like next to the
    // swatch: the swatch has nothing to show for it either.
    final color = parseSpoolColor(hex);
    return dashPickerField(
      context,
      id: 'spool_form.color',
      label: l10n.inventoryFieldColorHex,
      placeholder: l10n.inventoryColorNone,
      value: color == null ? null : hex.toUpperCase(),
      valueStyle: t.monoValue,
      leading: SpoolSwatch(rgba: hex.isEmpty ? null : hex, size: 24, radius: 6),
      trailingIcon: Icons.colorize,
      onTap: () => _openColorPicker(l10n),
      // The row this shares with the colour-name field carries the spacing.
      padding: EdgeInsets.zero,
    );
  }

  /// Color picker dialog. Starts from current color (or white), saves chosen hex
  /// `RRGGBBAA` to `rgba` field on confirm. Preserves existing alpha byte (usually `FF`) —
  /// picker edits RGB only, so we don't lose spool alpha (if ever non-full).
  Future<void> _openColorPicker(AppLocalizations l10n) async {
    final rawCurrent = _c['rgba']!.text.trim().replaceFirst('#', '');
    final alphaHex = rawCurrent.length == 8
        ? rawCurrent.substring(6, 8).toUpperCase()
        : 'FF';
    var picked = parseSpoolColor(_c['rgba']!.text) ?? const Color(0xFFFFFFFF);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.inventoryColorPickTitle),
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: picked,
            onColorChanged: (c) => picked = c,
            enableAlpha: false,
            hexInputBar: true,
            labelTypes: const [],
            portraitOnly: true,
            pickerAreaHeightPercent: 0.7,
          ),
        ),
        actions: [
          logTag(
            'spool_color.cancel',
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.cancel),
            ),
          ),
          logTag(
            'spool_color.confirm',
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.inventoryColorSelect),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      setState(() {
        _c['rgba']!.text = colorToHex(picked, enableAlpha: false) + alphaHex;
      });
    }
  }

  Widget _field(
    String key,
    String label, {
    bool number = false,
    String? hint,
    String? suffixText,
    int maxLines = 1,
    ValueChanged<String>? onChanged,
  }) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    return logTag(
      _fieldTag(key),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: TextFormField(
          controller: _c[key],
          style: t.body,
          keyboardType: number
              ? const TextInputType.numberWithOptions(decimal: true)
              : (maxLines > 1 ? TextInputType.multiline : TextInputType.text),
          maxLines: maxLines,
          textCapitalization: number
              ? TextCapitalization.none
              : TextCapitalization.sentences,
          onChanged: onChanged,
          decoration: dashDecoration(
            t,
            labelText: label,
            hintText: hint,
            suffixText: suffixText,
          ),
          validator: (v) {
            final text = (v ?? '').trim();
            if (!number || text.isEmpty) return null;
            final value = parseUserDecimal(text);
            if (value == null) return l10n.inventoryFieldInvalidNumber;
            // Same floor as the bulk sheet: the server takes a negative core
            // weight without a word and every remaining-weight sum built on it
            // is then wrong.
            if (value < 0) return l10n.inventoryFieldNegative;
            return null;
          },
        ),
        ),
    );
  }
}

/// `coreWeight` → `core_weight`: log identifiers are lowercase with
/// underscores, while the controller keys are camelCase. The replacement
/// callback lowercases each capital and puts an underscore in front of it.
///
/// [area] is the sheet the control lives on — the per-spool form or the
/// mass-edit sheet, which name their fields identically.
String _fieldTag(String key, {String area = 'spool_form'}) =>
    '$area.${key.replaceAllMapped(RegExp(r'[A-Z]'), (m) => '_${m[0]!.toLowerCase()}')}';

/// A trimmed field value, or null when the user left it blank. Blank means
/// "unset" on both sheets: the form sends no key rather than an empty string,
/// and the mass-edit patch leaves the field alone.
String? _trimmedField(Map<String, TextEditingController> c, String key) {
  final v = c[key]!.text.trim();
  return v.isEmpty ? null : v;
}

/// An integer-typed field, parsed with the same tolerance as its validator:
/// every numeric field on both sheets is validated as a decimal, so a decimal
/// has to round here rather than come out null — see [parseUserRoundedInt].
int? _intField(Map<String, TextEditingController> c, String key) =>
    parseUserRoundedInt(c[key]!.text);


/// Color picker: large preview + popular swatches from database + search.
/// Tap color fills hex/name/gradient/effect in form (via [onPick]).
class _ColorPicker extends ConsumerWidget {
  const _ColorPicker({
    required this.rgba,
    required this.query,
    required this.onQuery,
    required this.onPick,
  });

  final String rgba;
  final String query;
  final ValueChanged<String> onQuery;
  final ValueChanged<ColorEntry> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final colors = ref.watch(colorCatalogProvider).valueOrNull ?? const [];
    final preview = parseSpoolColor(rgba);
    final selectedHex = normalizeRgba(rgba);

    final q = query.trim().toLowerCase();
    final List<ColorEntry> shown;
    if (q.isEmpty) {
      shown = colors.where((c) => c.isDefault).take(18).toList();
    } else {
      shown = colors
          .where(
            (c) =>
                c.colorName.toLowerCase().contains(q) ||
                c.manufacturer.toLowerCase().contains(q) ||
                (c.material?.toLowerCase().contains(q) ?? false),
          )
          .take(24)
          .toList();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 40,
          decoration: BoxDecoration(
            color: preview ?? t.subCard,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: t.subCardBorder),
          ),
        ),
        const SizedBox(height: 8),
        if (colors.isNotEmpty) ...[
          DashSearchField(
            id: 'spool_form.color_search',
            hintText: l10n.inventoryColorSearchHint,
            onChanged: onQuery,
          ),
          const SizedBox(height: 8),
          if (q.isEmpty)
            Text(
              l10n.inventoryColorCommon,
              style: t.microSoft,
            ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in shown)
                _ColorChip(
                  entry: c,
                  selected: normalizeRgba(c.hexColor) == selectedHex,
                  onTap: () => onPick(c),
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _ColorChip extends StatelessWidget {
  const _ColorChip({
    required this.entry,
    required this.onTap,
    this.selected = false,
  });

  final ColorEntry entry;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final color = parseSpoolColor(entry.hexColor);
    return Tooltip(
      message: entry.colorName,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color ?? t.subCard,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? t.accentGreen : t.subCardBorder,
              width: selected ? 2 : 1,
            ),
          ),
          child: color == null
              ? Icon(
                  Icons.question_mark,
                  size: 16,
                  color: t.textTertiary,
                )
              : null,
        ),
      ).tagged('spool_form.color_swatch'),
    );
  }
}

/// Searchable slicer-filament preset picker (bottom sheet). Reuses the slice
/// modal's [slicerPresetsProvider] (unified local/cloud/standard tiers). Returns
/// the chosen [SlicerPreset] via `Navigator.pop`, or null on dismiss. Degrades
/// with a clear message when slicing is disabled or presets are unavailable.
class _SlicerPresetPicker extends ConsumerStatefulWidget {
  const _SlicerPresetPicker({this.printerModel, this.material});

  /// The printer model the preset is being chosen for, when the picker was
  /// opened from a per-model row. Null from the spool's own preset field —
  /// that one is not about any particular printer.
  final String? printerModel;

  /// What the spool is made of, as the form has it. Empty while the material
  /// field is still blank, which is the normal case on a new spool.
  final String? material;

  @override
  ConsumerState<_SlicerPresetPicker> createState() =>
      _SlicerPresetPickerState();
}

class _SlicerPresetPickerState extends ConsumerState<_SlicerPresetPicker> {
  String _query = '';

  /// Both filters start on: the caller only passes a value it is sure of, and
  /// the list they narrow runs to hundreds of entries. Off is one tap away,
  /// which is what makes hiding anything at all defensible.
  bool _byModel = true;
  bool _byMaterial = true;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final async = ref.watch(slicerPresetsProvider);
    final model = widget.printerModel?.trim() ?? '';
    final material = widget.material?.trim() ?? '';
    // Without the registry the model filter classifies nothing and hides
    // nothing, so the chip stays honest while it loads.
    final registry =
        ref.watch(printerModelRegistryProvider).valueOrNull ?? const {};

    return DraggableSheetSurface(
      builder: (context, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.inventoryFieldSlicerPreset,
                  style: t.display,
                ),
                const SizedBox(height: 8),
                DashSearchField(
                  id: 'spool_form.preset_search',
                  autofocus: true,
                  hintText: l10n.inventorySlicerPresetSearch,
                  onChanged: (v) => setState(() => _query = v),
                ),
                if (model.isNotEmpty || material.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        // No avatar: the app's chips say "on" with the
                        // theme's checkmark, and an icon sits in exactly that
                        // slot — a filter that looked unlike every other
                        // filter in the app.
                        if (model.isNotEmpty)
                          FilterChip(
                            label: Text(model),
                            selected: _byModel,
                            onSelected: (v) => setState(() => _byModel = v),
                          ).tagged('spool_form.preset_filter_model'),
                        if (material.isNotEmpty)
                          FilterChip(
                            label: Text(material),
                            selected: _byMaterial,
                            onSelected: (v) => setState(() => _byMaterial = v),
                          ).tagged('spool_form.preset_filter_material'),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: async.when(
              loading: () =>
                  const DashLoading(),
              error: (_, _) => _message(
                context,
                controller,
                l10n.inventorySlicerPresetUnavailable,
              ),
              data: (presets) {
                final items = filterFilamentPresets(
                  presets.filaments,
                  query: _query,
                  printerModel: _byModel ? model : null,
                  printerModels: registry,
                  material: _byMaterial ? material : null,
                );
                if (items.isEmpty) {
                  return _message(
                    context,
                    controller,
                    presets.filaments.isEmpty
                        ? l10n.inventorySlicerPresetUnavailable
                        : l10n.inventoryNoMatches,
                  );
                }
                // The rows are `ListTile`s and the sheet's surface is a
                // painted `DecoratedBox`, which would swallow their ink: a
                // tile paints its splash on the nearest Material ancestor,
                // and without one here the framework says so on every build.
                return Material(
                  type: MaterialType.transparency,
                  child: ListView.builder(
                  controller: controller,
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final p = items[i];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.tune),
                      title: Text(
                        p.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        p.filamentType == null || p.filamentType!.isEmpty
                            ? p.source
                            : '${p.filamentType} · ${p.source}',
                      ),
                      onTap: () => Navigator.of(context).pop(p),
                    ).tagged('spool_form.preset_option');
                  },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Empty/error placeholder that stays scrollable so the sheet's drag-to-resize
  /// keeps working even with no list to scroll.
  Widget _message(
    BuildContext context,
    ScrollController controller,
    String text,
  ) {
    return ListView(
      controller: controller,
      children: [
        Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Searchable empty-spool (core weight) picker (bottom sheet). Lists the
/// server core-weight catalog from [coreWeightsProvider]; returns the chosen
/// [CoreWeightEntry] via `Navigator.pop`, or null on dismiss.
class _CoreWeightPicker extends ConsumerStatefulWidget {
  const _CoreWeightPicker();

  @override
  ConsumerState<_CoreWeightPicker> createState() => _CoreWeightPickerState();
}

class _CoreWeightPickerState extends ConsumerState<_CoreWeightPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final cores = ref.watch(coreWeightsProvider).valueOrNull ?? const [];
    final q = _query.trim().toLowerCase();
    final items = [
      for (final c in cores)
        if (q.isEmpty ||
            c.name.toLowerCase().contains(q) ||
            c.weight.toString().contains(q))
          c,
    ];

    return DraggableSheetSurface(
      builder: (context, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.inventoryFieldEmptySpoolWeight,
                  style: t.display,
                ),
                const SizedBox(height: 8),
                DashSearchField(
                  id: 'spool_form.core_search',
                  autofocus: true,
                  hintText: l10n.inventoryCoreWeightSearch,
                  onChanged: (v) => setState(() => _query = v),
                ),
              ],
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? ListView(
                    controller: controller,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Center(
                          child: Text(
                            l10n.inventoryNoMatches,
                            textAlign: TextAlign.center,
                            style: t.bodyPlain.copyWith(color: t.textTertiary),
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    controller: controller,
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final c = items[i];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.donut_large),
                        title: Text(
                          c.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text('${c.weight} g'),
                        onTap: () => Navigator.of(context).pop(c),
                      ).tagged('spool_form.core_option');
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _FormSection extends StatelessWidget {
  const _FormSection({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        label.toUpperCase(),
        style: t.micro.copyWith(color: t.accentGreenInk, letterSpacing: 1.2),
      ),
    );
  }
}
