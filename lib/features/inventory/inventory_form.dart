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
    final measured = double.tryParse(raw.trim());
    if (measured == null) return;
    final core = double.tryParse(_c['coreWeight']!.text.trim()) ?? 0;
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
    final remaining = double.tryParse(_c['remaining']!.text.trim());
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
      costPerKg: double.tryParse(_c['costPerKg']!.text.trim()),
      category: _trim('category'),
      lowStockThresholdPct: lowStock,
      storageLocation: _trim('location'),
      slicerFilament: _slicerFilament,
      slicerFilamentName: _slicerFilamentName,
      note: _trim('note'),
    );
    setState(() => _saving = true);
    final notifier = ref.read(inventoryProvider.notifier);
    try {
      final String message;
      if (_isEdit) {
        await notifier.updateSpool(widget.existing!.id, draft);
        message = l10n.inventorySpoolUpdated;
      } else if (_quantity > 1) {
        final created = await notifier.bulkCreateSpools(draft, _quantity);
        message = l10n.inventorySpoolsCreated(created);
      } else {
        await notifier.createSpool(draft);
        message = l10n.inventorySpoolCreated;
      }
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

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (context, controller) => SheetSurface(child: Form(
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
                final labelInt = int.tryParse(_c['labelWeight']!.text.trim());
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
      )),
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
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _openCoreWeightPicker(l10n),
              child: InputDecorator(
                decoration: dashDecoration(
                  t,
                  labelText: l10n.inventoryFieldEmptySpoolWeight,
                  suffixIcon: Icon(Icons.arrow_drop_down, color: t.textTertiary),
                ),
                child: Text(
                  selected?.name ?? l10n.inventoryCoreWeightSelect,
                  style: t.body.copyWith(color: selected == null ? t.textTertiary : t.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ).tagged('spool_form.core_weight'),
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
    final t = DashTokens.of(context);
    final selected = _slicerFilamentName ?? _slicerFilament;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openSlicerPresetPicker(l10n),
        child: InputDecorator(
          decoration: dashDecoration(
            t,
            labelText: l10n.inventoryFieldSlicerPreset,
            helperText: l10n.inventorySlicerPresetHint,
            prefixIcon: Icon(Icons.tune, color: t.textTertiary),
            suffixIcon: selected == null
                ? Icon(Icons.arrow_drop_down, color: t.textTertiary)
                : IconButton(
                    icon: Icon(Icons.clear, color: t.textTertiary),
                    tooltip: l10n.clear,
                    onPressed: () => setState(() {
                      _slicerFilament = null;
                      _slicerFilamentName = null;
                    }),
                  ),
          ),
          child: Text(
            selected ?? l10n.inventorySlicerPresetNone,
            style: t.body.copyWith(color: selected == null ? t.textTertiary : t.textPrimary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ).tagged('spool_form.preset'),
    );
  }

  /// Opens the preset picker; on selection stores id+name and, when material is
  /// still blank, seeds it from the preset's filament type (cheap auto-fill).
  Future<void> _openSlicerPresetPicker(AppLocalizations l10n) async {
    final picked = await dashSurfaceSheet<SlicerPreset>(
      context,
      builder: (_) => const _SlicerPresetPicker(),
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

  /// Color field: instead of manual hex entry, opens color picker (HSV wheel + hex bar).
  /// On selection, writes hex `RRGGBBAA` to `rgba` controller (alpha preserved
  /// from previous value, default `FF`).
  Widget _hexColorPickerField(AppLocalizations l10n) {
    final t = DashTokens.of(context);
    final hex = _c['rgba']!.text.trim();
    final color = parseSpoolColor(hex);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _openColorPicker(l10n),
      child: InputDecorator(
        decoration: dashDecoration(
          t,
          labelText: l10n.inventoryFieldColorHex,
          suffixIcon: Icon(Icons.colorize, color: t.textTertiary),
        ),
        child: Row(
          children: [
            SpoolSwatch(rgba: hex.isEmpty ? null : hex, size: 24, radius: 6),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                hex.isEmpty ? l10n.inventoryColorNone : hex.toUpperCase(),
                style: t.monoValue.copyWith(color: color == null ? t.textTertiary : t.textPrimary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    ).tagged('spool_form.color');
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
            if (number && text.isNotEmpty && double.tryParse(text) == null) {
              return l10n.inventoryFieldInvalidNumber;
            }
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

/// An integer-typed field parsed with the same tolerance as its validator
/// (`double.tryParse`) — a plain `int.tryParse` would silently drop a value
/// like "1000.5" (passes validation as a valid number, but is not a valid
/// int), sending `null` instead of a rounded weight.
int? _intField(Map<String, TextEditingController> c, String key) =>
    double.tryParse(c[key]!.text.trim())?.round();


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
  const _SlicerPresetPicker();

  @override
  ConsumerState<_SlicerPresetPicker> createState() =>
      _SlicerPresetPickerState();
}

class _SlicerPresetPickerState extends ConsumerState<_SlicerPresetPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final async = ref.watch(slicerPresetsProvider);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (context, controller) => SheetSurface(child: Column(
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
                final q = _query.trim().toLowerCase();
                final items = [
                  for (final p in presets.filaments)
                    if (q.isEmpty ||
                        p.name.toLowerCase().contains(q) ||
                        p.id.toLowerCase().contains(q))
                      p,
                ];
                if (items.isEmpty) {
                  return _message(
                    context,
                    controller,
                    presets.filaments.isEmpty
                        ? l10n.inventorySlicerPresetUnavailable
                        : l10n.inventoryNoMatches,
                  );
                }
                return ListView.builder(
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
                );
              },
            ),
          ),
        ],
      )),
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

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (context, controller) => SheetSurface(child: Column(
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
      )),
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
