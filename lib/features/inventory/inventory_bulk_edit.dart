part of 'inventory_screen.dart';

/// Mass edit of the selected spools: one partial patch applied to all of them.
///
/// Every field starts blank and a blank field is left alone — there is
/// deliberately no way to *clear* a value across a selection, so a mis-tap
/// cannot blank a note or a location on twenty spools. Clearing stays in the
/// per-spool form, where it is one spool at a time. The web client made the
/// same call on issue #1795, and the two clients agreeing matters more here
/// than either shape on its own.
///
/// Pops with the [BulkOutcome] on success and stays open on a refusal, so the
/// typed values survive a retry.
class _BulkEditSheet extends ConsumerStatefulWidget {
  const _BulkEditSheet({required this.spoolIds});

  final Set<int> spoolIds;

  @override
  ConsumerState<_BulkEditSheet> createState() => _BulkEditSheetState();
}

class _BulkEditSheetState extends ConsumerState<_BulkEditSheet> {
  final _formKey = GlobalKey<FormState>();

  /// One controller per editable field. Keys match [SpoolBulkPatch]'s fields,
  /// not the wire names — [_patch] does that translation.
  final _c = <String, TextEditingController>{
    for (final key in [
      'material',
      'brand',
      'subtype',
      'colorName',
      'rgba',
      'labelWeight',
      'coreWeight',
      'costPerKg',
      'category',
      'lowStock',
      'location',
      'note',
    ])
      key: TextEditingController(),
  };

  String? _slicerFilament;
  String? _slicerFilamentName;
  bool _saving = false;

  int get _count => widget.spoolIds.length;

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  String? _trim(String key) {
    final v = _c[key]!.text.trim();
    return v.isEmpty ? null : v;
  }

  /// Same tolerance as the field's own validator: `int.tryParse` would drop
  /// "1000.5" — a valid number that is not a valid int — and send nothing.
  int? _int(String key) => double.tryParse(_c[key]!.text.trim())?.round();

  SpoolBulkPatch _patch() => SpoolBulkPatch(
        material: _trim('material'),
        brand: _trim('brand'),
        subtype: _trim('subtype'),
        colorName: _trim('colorName'),
        rgba: normalizeRgba(_c['rgba']!.text),
        labelWeight: _int('labelWeight'),
        coreWeight: _int('coreWeight'),
        costPerKg: double.tryParse(_c['costPerKg']!.text.trim()),
        category: _trim('category'),
        // Server takes 1..99 and answers 422 outside it.
        lowStockThresholdPct: _int('lowStock')?.clamp(1, 99),
        storageLocation: _trim('location'),
        slicerFilament: _slicerFilament,
        slicerFilamentName: _slicerFilamentName,
        note: _trim('note'),
      );

  Future<void> _apply() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    // Validation before the confirmation, or a typo in a number would be
    // dropped from the patch and the tally would still report success.
    if (!_formKey.currentState!.validate()) return;
    final patch = _patch();
    if (patch.isEmpty) return;

    final confirmed = await confirmDialog(
      context,
      id: 'bulk_edit.apply',
      title: l10n.inventoryBulkEditConfirmTitle(_count),
      message: l10n.inventoryBulkEditConfirmBody(patch.fieldCount),
      confirmLabel: l10n.inventoryApply,
    );
    if (!confirmed || !mounted) return;

    setState(() => _saving = true);
    try {
      final outcome = await ref
          .read(inventoryProvider.notifier)
          .bulkUpdateSpools(widget.spoolIds, patch);
      if (!mounted) return;
      Navigator.of(context).pop(outcome);
    } on AppApiException catch (e) {
      if (mounted) setState(() => _saving = false);
      showApiFailure(
        mounted ? messenger : null,
        e,
        l10n,
        action: 'bulk_edit.apply',
        // A 404 here is the server saying it has no bulk-update route at all
        // (it predates 0.2.5b1), which the generic wording would report as a
        // missing spool.
        message: e.statusCode == 404 ? l10n.inventoryBulkEditUnsupported : null,
      );
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

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (context, controller) => SheetSurface(
        child: Form(
          key: _formKey,
          child: ListView(
            controller: controller,
            padding: EdgeInsets.fromLTRB(16, 0, 16, 24 + bottomInset),
            children: [
              Text(l10n.inventoryBulkEditTitle(_count), style: t.display),
              const SizedBox(height: 4),
              Text(l10n.inventoryBulkEditHint, style: t.bodySoft),
              const SizedBox(height: 12),

              _FormSection(label: l10n.inventorySectionFilament),
              _presetField(l10n),
              _combo('material', l10n.inventoryFieldMaterial,
                  ref.watch(materialOptionsProvider)),
              _combo('brand', l10n.inventoryFieldBrand,
                  ref.watch(brandOptionsProvider)),
              _combo('subtype', l10n.inventoryFieldSubtype,
                  ref.watch(subtypeOptionsProvider)),
              _field('labelWeight', l10n.inventoryFieldLabelWeight,
                  number: true),

              const SizedBox(height: 8),
              _FormSection(label: l10n.inventorySectionColor),
              _field('colorName', l10n.inventoryFieldColorName),
              ValueListenableBuilder(
                valueListenable: _c['rgba']!,
                builder: (context, _, _) => _colorField(l10n),
              ),

              const SizedBox(height: 8),
              _FormSection(label: l10n.inventorySectionAdditional),
              _field('coreWeight', l10n.inventoryFieldEmptySpoolWeight,
                  number: true),
              _field('costPerKg', l10n.inventoryFieldCostPerKg, number: true),
              _field('category', l10n.inventoryFieldCategory),
              _field('lowStock', l10n.inventoryFieldLowStock,
                  number: true, hint: l10n.inventoryLowStockHint),
              _combo('location', l10n.inventoryFieldLocation,
                  ref.watch(locationOptionsProvider)),
              _field('note', l10n.inventoryFieldNote, maxLines: 3),

              const SizedBox(height: 20),
              _applyButton(t, l10n),
            ],
          ),
        ),
      ),
    );
  }

  /// Apply stays disabled until something is actually filled in — the route
  /// refuses an empty patch, and a button that fires a 400 is worse than a
  /// button that says "nothing to do yet".
  Widget _applyButton(DashTokens t, AppLocalizations l10n) => ListenableBuilder(
        // One listenable for all twelve fields, so typing anywhere re-evaluates
        // the button without a setState on every keystroke.
        listenable: Listenable.merge(_c.values.toList()),
        builder: (context, _) => SizedBox(
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
            onPressed: _saving || _patch().isEmpty ? null : _apply,
            child: _saving
                ? DashSpinner(size: 20, color: _onAccentGreen)
                : Text(
                    l10n.inventoryBulkEditApply(_count),
                    style: const TextStyle(
                      fontFamily: DashTokens.fontUi,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
          ).tagged('bulk_edit.apply'),
        ),
      );

  /// Editable combo: pick from what the shelf already uses, or type a new
  /// value. Same widget the per-spool form uses, minus the required marker —
  /// nothing is required here.
  Widget _combo(String key, String label, List<String> options) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: dashCombo<String>(
          context,
          id: _bulkFieldTag(key),
          controller: _c[key],
          label: Text(label),
          filterable: true,
          textStyle: DashTokens.of(context).body,
          entries: [
            for (final o in options)
              DropdownMenuEntry(
                value: o,
                label: o,
                labelWidget: logTagMaterial(
                    '${_bulkFieldTag(key)}.option', o, Text(o)),
              ),
          ],
        ),
      );

  Widget _field(
    String key,
    String label, {
    bool number = false,
    String? hint,
    int maxLines = 1,
  }) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    return logTag(
      _bulkFieldTag(key),
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
          decoration: dashDecoration(t, labelText: label, hintText: hint),
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

  /// Slicer preset for the whole selection. Clearing it means "leave every
  /// spool's preset as it is" — it does not unset the preset server-side.
  Widget _presetField(AppLocalizations l10n) {
    final t = DashTokens.of(context);
    final selected = _slicerFilamentName ?? _slicerFilament;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          final picked = await dashSurfaceSheet<SlicerPreset>(
            context,
            builder: (_) => const _SlicerPresetPicker(),
          );
          if (picked == null || !mounted) return;
          setState(() {
            _slicerFilament = picked.id;
            _slicerFilamentName = picked.name;
          });
        },
        child: InputDecorator(
          decoration: dashDecoration(
            t,
            labelText: l10n.inventoryFieldSlicerPreset,
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
            selected ?? l10n.inventoryBulkEditUnchanged,
            style: t.body.copyWith(
              color: selected == null ? t.textTertiary : t.textPrimary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ).tagged('bulk_edit.preset'),
    );
  }

  /// Colour for the whole selection, picked rather than typed, so the hex that
  /// reaches the patch is always the 8-char form the server accepts — one bad
  /// hex would fail the entire batch with a 422.
  Widget _colorField(AppLocalizations l10n) {
    final t = DashTokens.of(context);
    final hex = _c['rgba']!.text.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _pickColor(l10n),
        child: InputDecorator(
          decoration: dashDecoration(
            t,
            labelText: l10n.inventoryFieldColorHex,
            suffixIcon: hex.isEmpty
                ? Icon(Icons.colorize, color: t.textTertiary)
                : IconButton(
                    icon: Icon(Icons.clear, color: t.textTertiary),
                    tooltip: l10n.clear,
                    onPressed: () => _c['rgba']!.clear(),
                  ),
          ),
          child: Row(
            children: [
              SpoolSwatch(rgba: hex.isEmpty ? null : hex, size: 24, radius: 6),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hex.isEmpty
                      ? l10n.inventoryBulkEditUnchanged
                      : hex.toUpperCase(),
                  style: t.monoValue.copyWith(
                    color: hex.isEmpty ? t.textTertiary : t.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ).tagged('bulk_edit.color'),
    );
  }

  Future<void> _pickColor(AppLocalizations l10n) async {
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
            'bulk_edit_color.cancel',
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.cancel),
            ),
          ),
          logTag(
            'bulk_edit_color.confirm',
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.inventoryColorSelect),
            ),
          ),
        ],
      ),
    );
    // Alpha is not editable here and every selected spool keeps its own, so the
    // patch always carries the opaque form.
    if (confirmed == true && mounted) {
      _c['rgba']!.text = '${colorToHex(picked, enableAlpha: false)}FF';
    }
  }
}

/// `coreWeight` → `bulk_edit.core_weight`, the same camelCase-to-snake_case
/// reduction [_fieldTag] does for the per-spool form.
String _bulkFieldTag(String key) =>
    'bulk_edit.${key.replaceAllMapped(RegExp(r'[A-Z]'), (m) => '_${m[0]!.toLowerCase()}')}';
