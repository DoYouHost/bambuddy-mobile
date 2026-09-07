import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diagnostics/log_tag.dart';
import '../../core/models/inventory_reference.dart' show ColorEntry;
import '../../core/models/swatch_code.dart';
import '../../core/theme/dash_text.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../common/confirm_dialog.dart';
import '../common/dash_search_field.dart';
import '../common/dash_sheet.dart';
import '../common/dash_snack.dart';
import '../common/device_files.dart';
import '../common/sliver_search_bar.dart';
import '../common/section_heading.dart';
import '../inventory/inventory_providers.dart'
    show colorCatalogProvider, inventoryProvider;
import '../inventory/inventory_screen.dart' show parseSpoolColor;
import 'swatch_providers.dart';

/// Swatch codes screen: create and manually edit 6-char codes for filament
/// DEFINITIONS (brand + type + variant + color, not specific spool), search by
/// code/name, list uncoded filaments from inventory, and export/import entire
/// registry as JSON file (import overwrites all, with warning).
class SwatchesScreen extends ConsumerStatefulWidget {
  const SwatchesScreen({super.key});

  @override
  ConsumerState<SwatchesScreen> createState() => _SwatchesScreenState();
}

class _SwatchesScreenState extends ConsumerState<SwatchesScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  AppLocalizations get _l10n => AppLocalizations.of(context);

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).snack(msg, duration: const Duration(seconds: 3));
  }

  // --- Export / import ---

  Future<void> _export() async {
    final l10n = _l10n;
    final codes = ref.read(swatchCodesProvider);
    if (codes.isEmpty) {
      _snack(l10n.swatchExportEmpty);
      return;
    }
    final payload = {
      'version': 1,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'codes': [for (final c in codes) c.toJson()],
    };
    final bytes = utf8.encode(
      const JsonEncoder.withIndent('  ').convert(payload),
    );
    final saved = await saveBytesToDevice(
      dialogTitle: l10n.swatchExport,
      fileName: 'swatch-codes.json',
      bytes: bytes,
    );
    if (!mounted) return;
    switch (saved.outcome) {
      case DeviceFileOutcome.cancelled:
        return;
      case DeviceFileOutcome.failed:
        _snack(l10n.swatchExportFailed);
      case DeviceFileOutcome.done:
        _snack(l10n.swatchExported(codes.length));
    }
  }

  Future<void> _import() async {
    final l10n = _l10n;
    final picked = await pickFileFromDevice(
      allowedExtensions: const ['json'],
      withData: true,
    );
    if (!mounted) return;
    if (picked.outcome == DeviceFileOutcome.failed) {
      _snack(l10n.swatchImportFailed);
      return;
    }
    final bytes = picked.file?.bytes;
    if (bytes == null) return; // Cancelled

    final List<SwatchCode> incoming;
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      final list = decoded is List
          ? decoded
          : (decoded is Map<String, dynamic> ? decoded['codes'] : null);
      if (list is! List) {
        _snack(l10n.swatchImportFailed);
        return;
      }
      incoming = [
        for (final e in list)
          if (e is Map<String, dynamic>) SwatchCode.fromJson(e),
      ].where((c) => c.code.isNotEmpty).toList();
    } on Object {
      _snack(l10n.swatchImportFailed);
      return;
    }

    if (incoming.isEmpty) {
      _snack(l10n.swatchImportEmpty);
      return;
    }

    final existing = ref.read(swatchCodesProvider).length;
    final confirmed = await confirmDialog(
      context,
      icon: Icons.warning_amber_rounded,
      title: l10n.swatchImportTitle,
      message: l10n.swatchImportWarning(existing, incoming.length),
      confirmLabel: l10n.swatchImportConfirm,
      id: 'swatch_import',
    );
    if (!confirmed || !mounted) return;

    await ref.read(swatchCodesProvider.notifier).replaceAll(incoming);
    if (!mounted) return;
    _snack(l10n.swatchImported(incoming.length));
  }

  // --- Tworzenie / edycja / usuwanie ---

  /// Open create sheet (initial == null) or edit existing code.
  Future<void> _openForm({SwatchCode? initial}) async {
    final l10n = _l10n;
    final result = await dashSheet<SwatchCode>(
      context,
      builder: (_) => _SwatchFormSheet(initial: initial),
    );
    if (result == null || !mounted) return;
    await ref
        .read(swatchCodesProvider.notifier)
        .save(result, replacingCode: initial?.code);
    if (!mounted) return;
    _snack(
      initial == null
          ? l10n.swatchCreatedSnack(result.code)
          : l10n.swatchUpdatedSnack(result.code),
    );
  }

  /// Quick code generation for inventory filament (no form).
  Future<void> _generateFor(FilamentIdentity identity) async {
    final l10n = _l10n;
    final notifier = ref.read(swatchCodesProvider.notifier);
    final already = ref
        .read(swatchCodesProvider)
        .any((c) => c.identityKey == identity.key);
    if (already) {
      _snack(l10n.swatchExists);
      return;
    }
    final created = await notifier.add(
      material: identity.material,
      brand: identity.brand,
      variant: identity.variant,
      colorName: identity.colorName,
      rgba: identity.rgba,
    );
    if (!mounted) return;
    _snack(l10n.swatchCreatedSnack(created.code));
  }

  Future<void> _confirmDelete(SwatchCode c) async {
    final confirmed = await confirmDialog(
      context,
      title: _l10n.swatchDeleteTitle,
      message: _l10n.swatchDeleteBody(c.code, c.displayName),
      confirmLabel: _l10n.swatchDelete,
      destructive: true,
      id: 'swatch_delete',
    );
    if (!confirmed || !mounted) return;
    await ref.read(swatchCodesProvider.notifier).remove(c.code);
  }

  void _copy(String code) {
    Clipboard.setData(ClipboardData(text: code));
    _snack(_l10n.swatchCopied(code));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n;
    final t = DashTokens.of(context);
    final query = ref.watch(swatchQueryProvider);
    final normalizedQuery = normalizeSwatchCode(query);
    final allCodes = ref.watch(swatchCodesProvider);
    final uncoded = ref.watch(uncodedFilamentsProvider);
    final inventoryLoaded = ref.watch(inventoryProvider).hasValue;

    final codes = query.trim().isEmpty
        ? allCodes
        : allCodes.where((c) {
            return c.code.contains(normalizedQuery) ||
                c.displayName.toLowerCase().contains(
                  query.trim().toLowerCase(),
                );
          }).toList();

    // Flattened once per build (cheap widget construction); the sliver list
    // below only lays out/mounts items near the viewport instead of all of
    // them eagerly (matters once the registry grows to hundreds of codes).
    final items = <Widget>[
      _SectionHeader(label: l10n.swatchSectionCodes, count: codes.length),
      if (codes.isEmpty)
        _EmptyHint(
          icon: Icons.qr_code_2_rounded,
          title: allCodes.isEmpty
              ? l10n.swatchNoCodes
              : l10n.swatchNoMatch(query.trim()),
          subtitle: allCodes.isEmpty ? l10n.swatchNoCodesHint : null,
        )
      else
        for (final c in codes)
          _SwatchTile(
            code: c,
            onEdit: () => _openForm(initial: c),
            onCopy: () => _copy(c.code),
            onDelete: () => _confirmDelete(c),
          ),
      if (inventoryLoaded && uncoded.isNotEmpty) ...[
        const SizedBox(height: 10),
        _SectionHeader(label: l10n.swatchSectionUncoded, count: uncoded.length),
        for (final f in uncoded)
          _UncodedTile(identity: f, onGenerate: () => _generateFor(f)),
      ] else if (inventoryLoaded && allCodes.isNotEmpty) ...[
        const SizedBox(height: 10),
        _EmptyHint(
          icon: Icons.check_circle_outline_rounded,
          title: l10n.swatchAllCoded,
        ),
      ],
    ];

    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: dashAppBar(
          context,
          title: l10n.swatchCodesTitle,
          actions: [
            logTag(
              'swatches.import',
              IconButton(
                icon: const Icon(Icons.file_download_outlined),
                tooltip: l10n.swatchImport,
                onPressed: _import,
              ),
            ),
            logTag(
              'swatches.export',
              IconButton(
                icon: const Icon(Icons.file_upload_outlined),
                tooltip: l10n.swatchExport,
                onPressed: _export,
              ),
            ),
          ],
        ),
        floatingActionButton: logTag(
          'swatches.create',
          FloatingActionButton.extended(
            backgroundColor: t.accentGreen,
            foregroundColor: const Color(0xFF0A0C08),
            onPressed: () => _openForm(),
            icon: const Icon(Icons.add),
            label: Text(l10n.swatchNewCode),
          ),
        ),
        body: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            DashSliverSearchBar(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: DashSearchField(
                id: 'swatches.search',
                controller: _searchController,
                hintText: l10n.swatchSearchHint,
                textCapitalization: TextCapitalization.characters,
                onChanged: (v) =>
                    ref.read(swatchQueryProvider.notifier).state = v,
              ),
            ),
            SliverPadding(
              // FAB floats above the system nav bar, so its clearance is the
              // button box plus that inset.
              padding: EdgeInsets.only(
                bottom: 96 + MediaQuery.viewPaddingOf(context).bottom,
              ),
              sliver: SliverList.builder(
                itemCount: items.length,
                itemBuilder: (context, i) => items[i],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Row(
        children: [
          SectionHeading(
            label.toUpperCase(),
            style: t.label.copyWith(
              color: t.accentGreenInk,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            decoration: BoxDecoration(
              color: t.subCard,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: t.subCardBorder),
            ),
            child: Text('$count', style: t.monoLabel),
          ),
        ],
      ),
    );
  }
}

/// Filament color swatch — rounded square. If missing/unparseable color:
/// neutral background with palette icon.
class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({required this.rgba, this.size = 46});

  final String? rgba;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final color = parseSpoolColor(rgba);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color ?? t.subCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.subCardBorder),
        boxShadow: color == null
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
      ),
      child: color == null
          ? Icon(Icons.palette_outlined, size: 20, color: t.textTertiary)
          : null,
    );
  }
}

/// Code chip — highlighted monospace on accent-tinted background.
class _CodeChip extends StatelessWidget {
  const _CodeChip({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: t.accentGreen.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: t.accentGreen.withValues(alpha: 0.4)),
      ),
      child: Text(
        code,
        style: t.monoTitle.copyWith(color: t.accentGreenInk, letterSpacing: 3),
      ),
    );
  }
}

class _SwatchTile extends StatelessWidget {
  const _SwatchTile({
    required this.code,
    required this.onEdit,
    required this.onCopy,
    required this.onDelete,
  });

  final SwatchCode code;
  final VoidCallback onEdit;
  final VoidCallback onCopy;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Material(
        color: Colors.transparent,
        child: logTag(
          'swatches.card',
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onEdit,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
              decoration: BoxDecoration(
                color: t.subCard,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: t.subCardBorder),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _ColorSwatch(rgba: code.rgba),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          code.displayName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: t.titleSm,
                        ),
                        const SizedBox(height: 7),
                        _CodeChip(code: code.code),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  logTag(
                    'swatches.copy',
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.copy_rounded, color: t.textSecondary),
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).copyButtonLabel,
                      onPressed: onCopy,
                    ),
                  ),
                  logTag(
                    'swatches.delete',
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.delete_outline_rounded, color: t.danger),
                      onPressed: onDelete,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UncodedTile extends StatelessWidget {
  const _UncodedTile({required this.identity, required this.onGenerate});

  final FilamentIdentity identity;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Material(
        color: Colors.transparent,
        child: logTag(
          'swatches.generate',
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onGenerate,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: t.subCard,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: t.subCardBorder),
              ),
              child: Row(
                children: [
                  _ColorSwatch(rgba: identity.rgba, size: 40),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      identity.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodyStrong,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Toned-down outlined style so the bold green FAB stays the
                  // single primary action and the two greens don't merge.
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: t.accentGreenInk,
                      side: BorderSide(
                        color: t.accentGreen.withValues(alpha: 0.55),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      textStyle: const TextStyle(
                        fontFamily: DashTokens.fontUi,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onPressed: onGenerate,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(l10n.swatchGenerate),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.icon, required this.title, this.subtitle});

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Column(
        children: [
          Icon(icon, size: 40, color: t.textTertiary),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: t.body.copyWith(color: t.textSecondary),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, textAlign: TextAlign.center, style: t.labelSoft),
          ],
        ],
      ),
    );
  }
}

/// Format text field to uppercase (swatch code).
class _UpperCaseFormatter extends TextInputFormatter {
  const _UpperCaseFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.copyWith(text: newValue.text.toUpperCase());
}

/// Code create/edit sheet. Material required; code manually editable (length/
/// alphabet/uniqueness validation) with regenerate button. Rest optional; color
/// as optional hex with preview.
class _SwatchFormSheet extends ConsumerStatefulWidget {
  const _SwatchFormSheet({this.initial});

  final SwatchCode? initial;

  @override
  ConsumerState<_SwatchFormSheet> createState() => _SwatchFormSheetState();
}

class _SwatchFormSheetState extends ConsumerState<_SwatchFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _code;
  late final TextEditingController _brand;
  late final TextEditingController _material;
  late final TextEditingController _variant;
  late final TextEditingController _colorName;
  late final TextEditingController _rgba;

  bool get _isEdit => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _code = TextEditingController(
      text: i?.code ?? ref.read(swatchCodesProvider.notifier).freshCode(),
    );
    _brand = TextEditingController(text: i?.brand ?? '');
    _material = TextEditingController(text: i?.material ?? '');
    _variant = TextEditingController(text: i?.variant ?? '');
    _colorName = TextEditingController(text: i?.colorName ?? '');
    _rgba = TextEditingController(text: i?.rgba ?? '');
  }

  @override
  void dispose() {
    _code.dispose();
    _brand.dispose();
    _material.dispose();
    _variant.dispose();
    _colorName.dispose();
    _rgba.dispose();
    super.dispose();
  }

  void _regenerate() {
    setState(() {
      _code.text = ref.read(swatchCodesProvider.notifier).freshCode();
    });
  }

  /// Open bambuddy color catalog browser (like in spool form). Selection fills
  /// color name AND hex (`rgba`); fields can still be edited manually after choice.
  Future<void> _pickColor() async {
    final entry = await dashSheet<ColorEntry>(
      context,
      builder: (_) => const _ColorCatalogSheet(),
    );
    if (entry == null) return;
    var hex = entry.hexColor.trim();
    if (hex.startsWith('#')) hex = hex.substring(1);
    setState(() {
      if (entry.colorName.isNotEmpty) _colorName.text = entry.colorName;
      _rgba.text = hex;
    });
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    String? clean(TextEditingController c) {
      final v = c.text.trim();
      return v.isEmpty ? null : v;
    }

    var rgba = _rgba.text.trim();
    if (rgba.startsWith('#')) rgba = rgba.substring(1);

    Navigator.pop(
      context,
      SwatchCode(
        code: normalizeSwatchCode(_code.text),
        material: _material.text.trim(),
        brand: clean(_brand),
        variant: clean(_variant),
        colorName: clean(_colorName),
        rgba: rgba.isEmpty ? null : rgba,
        createdAt:
            widget.initial?.createdAt ??
            DateTime.now().toUtc().toIso8601String(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final preview = parseSpoolColor(_rgba.text);
    final mq = MediaQuery.of(context);
    // The nav bar inset comes from [dashSheet]; what is left is the keyboard,
    // which no SafeArea covers.
    final bottomInset = mq.viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 4,
        bottom: bottomInset + 20,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _isEdit ? l10n.swatchEditTitle : l10n.swatchFormTitle,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  const _UpperCaseFormatter(),
                  LengthLimitingTextInputFormatter(swatchCodeLength),
                ],
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                  letterSpacing: 4,
                ),
                decoration: InputDecoration(
                  labelText: l10n.swatchFieldCode,
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.casino_outlined),
                    tooltip: l10n.swatchRegenerate,
                    onPressed: _regenerate,
                  ).tagged('swatch_form.regenerate'),
                ),
                validator: (v) {
                  final code = normalizeSwatchCode(v ?? '');
                  if (!isValidSwatchCode(code)) return l10n.swatchCodeInvalid;
                  final taken = ref
                      .read(swatchCodesProvider.notifier)
                      .hasCode(code, exclude: widget.initial?.code);
                  if (taken) return l10n.swatchCodeTaken;
                  return null;
                },
              ).tagged('swatch_form.code'),
              const SizedBox(height: 12),
              TextFormField(
                controller: _brand,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: l10n.swatchFieldBrand,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ).tagged('swatch_form.brand'),
              const SizedBox(height: 12),
              TextFormField(
                controller: _material,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: '${l10n.swatchFieldMaterial} *',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? l10n.swatchMaterialRequired
                    : null,
              ).tagged('swatch_form.material'),
              const SizedBox(height: 12),
              TextFormField(
                controller: _variant,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: l10n.swatchFieldVariant,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ).tagged('swatch_form.variant'),
              const SizedBox(height: 12),
              TextFormField(
                controller: _colorName,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: l10n.swatchFieldColor,
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.palette_outlined),
                    tooltip: l10n.inventoryColorPickTitle,
                    onPressed: _pickColor,
                  ).tagged('swatch_form.pick_color'),
                ),
              ).tagged('swatch_form.color_name'),
              const SizedBox(height: 12),
              TextFormField(
                controller: _rgba,
                decoration: InputDecoration(
                  labelText: l10n.swatchFieldHex,
                  hintText: 'RRGGBB',
                  prefixText: '#',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Container(
                      width: 24,
                      decoration: BoxDecoration(
                        color:
                            preview ??
                            theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant,
                        ),
                      ),
                    ),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ).tagged('swatch_form.rgba'),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: logTag(
                      'swatch_form.cancel',
                      OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(l10n.cancel),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: logTag(
                      'swatch_form.save',
                      FilledButton.icon(
                        onPressed: _submit,
                        icon: Icon(
                          _isEdit ? Icons.check : Icons.auto_awesome,
                          size: 18,
                        ),
                        label: Text(
                          _isEdit ? l10n.swatchSave : l10n.swatchGenerateCode,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Color selection sheet from bambuddy catalog (`/inventory/colors`). Searchable
/// by name/brand/material; no query shows defaults. Tap returns chosen [ColorEntry]
/// to form. Empty catalog (e.g. Spoolman backend) → hint to enter color manually.
class _ColorCatalogSheet extends ConsumerStatefulWidget {
  const _ColorCatalogSheet();

  @override
  ConsumerState<_ColorCatalogSheet> createState() => _ColorCatalogSheetState();
}

class _ColorCatalogSheetState extends ConsumerState<_ColorCatalogSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = ref.watch(colorCatalogProvider).valueOrNull ?? const [];
    final q = _query.trim().toLowerCase();

    final List<ColorEntry> shown;
    if (q.isEmpty) {
      shown = colors.where((c) => c.isDefault).take(60).toList();
    } else {
      shown = colors
          .where(
            (c) =>
                c.colorName.toLowerCase().contains(q) ||
                c.manufacturer.toLowerCase().contains(q) ||
                (c.material?.toLowerCase().contains(q) ?? false),
          )
          .take(80)
          .toList();
    }

    final mq = MediaQuery.of(context);
    final bottomInset = mq.viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 4,
        bottom: bottomInset + 12,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.inventoryColorPickTitle, style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          DashSearchField(
            id: 'swatches.color_search',
            hintText: l10n.inventoryColorSearchHint,
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 12),
          if (colors.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                l10n.swatchNoCatalogColors,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: shown.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final c = shown[i];
                  final color = parseSpoolColor(c.hexColor);
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color:
                            color ?? theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant,
                        ),
                      ),
                    ),
                    title: Text(c.colorName.isEmpty ? '—' : c.colorName),
                    subtitle: c.manufacturer.isEmpty
                        ? null
                        : Text(
                            c.manufacturer,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                    onTap: () => Navigator.pop(context, c),
                  ).tagged('swatch_form.color_option');
                },
              ),
            ),
        ],
      ),
    );
  }
}
