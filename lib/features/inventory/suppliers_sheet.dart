part of 'inventory_screen.dart';

/// The supplier master list: where filament is bought, kept apart from the
/// brand that made it. The same list in both inventory modes.
void _openSuppliers(BuildContext context) {
  dashSurfaceSheet<void>(context, builder: (_) => const _SuppliersSheet());
}

class _SuppliersSheet extends ConsumerWidget {
  const _SuppliersSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final list = ref.watch(supplierListProvider);

    return logTag(
      'sheet.suppliers',
      DraggableSheetSurface(
        initialSize: 0.6,
        minSize: 0.3,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(
            DashSpace.gutter,
            0,
            DashSpace.gutter,
            DashSpace.xl,
          ),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.inventorySuppliersTitle,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _openSupplierForm(context),
                  icon: const Icon(Icons.add),
                  label: Text(l10n.inventorySupplierAdd),
                ).tagged('suppliers.add'),
              ],
            ),
            InlineNote(
              l10n.inventorySuppliersHint,
              icon: Icons.info_outline,
              padding: const EdgeInsets.only(
                top: DashSpace.sm,
                bottom: DashSpace.xs,
              ),
            ),
            ...list.when(
              skipLoadingOnReload: true,
              loading: () => const [
                Padding(
                  padding: EdgeInsets.symmetric(vertical: DashSpace.xl),
                  child: DashLoading(),
                ),
              ],
              error: (_, _) => [
                InlineNote(l10n.inventorySuppliersLoadFailed, urgent: true),
              ],
              data: (suppliers) => suppliers.isEmpty
                  ? [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: DashSpace.xl,
                        ),
                        child: Text(
                          l10n.inventorySuppliersEmpty,
                          textAlign: TextAlign.center,
                          style: t.bodyPlain.copyWith(color: t.textSecondary),
                        ),
                      ),
                    ]
                  : [
                      for (final supplier in suppliers)
                        _SupplierRow(supplier: supplier),
                    ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SupplierRow extends ConsumerWidget {
  const _SupplierRow({required this.supplier});

  final Supplier supplier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final details = [
      ?supplier.website,
      if (supplier.customerNumber case final number?)
        l10n.inventorySupplierCustomerNumberValue(number),
    ];
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(color: t.subCardBorder),
    );
    return Padding(
      padding: const EdgeInsets.only(top: DashSpace.md),
      child: Material(
        color: t.subCard,
        shape: shape,
        child: ListTile(
          shape: shape,
          title: Text(supplier.name, style: t.titleSm),
          subtitle: details.isEmpty
              ? null
              : Text(
                  details.join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.label.copyWith(color: t.textSecondary),
                ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.inventorySpoolCount(supplier.spoolCount),
                style: t.label.copyWith(color: t.textSecondary),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: l10n.inventoryDelete,
                onPressed: () => _delete(context, ref),
              ).tagged('suppliers.delete'),
            ],
          ),
          onTap: () => _openSupplierForm(context, existing: supplier),
        ).tagged('suppliers.edit'),
      ),
    );
  }

  /// A supplier still on a spool is refused by the server (409), so the count
  /// it already sent says so before anyone confirms anything. The 409 is still
  /// handled: a spool can have been given this supplier since the list loaded.
  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (supplier.spoolCount > 0) {
      messenger.snack(l10n.inventorySupplierInUse(supplier.spoolCount));
      return;
    }
    final ok = await confirmDialog(
      context,
      id: 'suppliers.delete_confirm',
      title: l10n.inventorySupplierDeleteTitle(supplier.name),
      message: l10n.inventorySupplierDeleteBody,
      confirmLabel: l10n.inventoryDelete,
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    final repo = ref.read(suppliersRepositoryProvider);
    final container = ProviderScope.containerOf(context);
    try {
      await repo.deleteSupplier(supplier.id);
      messenger.snack(l10n.inventorySupplierDeleted);
    } on AppApiException catch (e) {
      if (e.statusCode == 409) {
        messenger.snack(l10n.inventorySupplierInUseUnknown);
      } else {
        showApiFailure(messenger, e, l10n, action: 'suppliers.delete');
      }
    } finally {
      container.invalidate(supplierListProvider);
    }
  }
}

/// Answers with the row the server saved, or null when the form was closed.
Future<Supplier?> _openSupplierForm(
  BuildContext context, {
  Supplier? existing,
}) => dashSurfaceSheet<Supplier>(
  context,
  builder: (_) => _SupplierFormSheet(existing: existing),
);

class _SupplierFormSheet extends ConsumerStatefulWidget {
  const _SupplierFormSheet({this.existing});

  final Supplier? existing;

  @override
  ConsumerState<_SupplierFormSheet> createState() => _SupplierFormSheetState();
}

class _SupplierFormSheetState extends ConsumerState<_SupplierFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _c;
  bool _saving = false;

  /// A 409 from the save, shown on the name field until the name is edited.
  bool _nameTaken = false;

  @override
  void initState() {
    super.initState();
    final s = widget.existing;
    _c = {
      'name': TextEditingController(text: s?.name ?? ''),
      'website': TextEditingController(text: s?.website ?? ''),
      'customerNumber': TextEditingController(text: s?.customerNumber ?? ''),
      'note': TextEditingController(text: s?.note ?? ''),
    };
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(suppliersRepositoryProvider);
    final container = ProviderScope.containerOf(context);
    final draft = SupplierDraft(
      name: _c['name']!.text.trim(),
      website: _trimmedField(_c, 'website'),
      customerNumber: _trimmedField(_c, 'customerNumber'),
      note: _trimmedField(_c, 'note'),
    );
    setState(() => _saving = true);
    try {
      final existing = widget.existing;
      final Supplier saved;
      if (existing == null) {
        saved = await repo.createSupplier(draft);
      } else {
        saved = await repo.updateSupplier(existing.id, draft);
        // Spools carry the supplier's name in their links; a rename has to
        // reach the list and the detail cards too.
        unawaited(container.read(inventoryProvider.notifier).refresh());
      }
      container.invalidate(supplierListProvider);
      if (!mounted) return;
      Navigator.of(context).pop(saved);
      messenger.snack(l10n.inventorySupplierSaved);
    } on AppApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _nameTaken = e.statusCode == 409;
      });
      if (!_nameTaken) {
        showApiFailure(messenger, e, l10n, action: 'supplier_form.save');
      }
    }
  }

  String? _validateName(AppLocalizations l10n, String? value) {
    final name = (value ?? '').trim();
    if (name.isEmpty) return l10n.inventoryFieldRequired;
    if (name.contains(SupplierDraft.nameSeparator)) {
      return l10n.inventorySupplierNameSeparator;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    Widget field(
      String key,
      String label, {
      required int maxLength,
      int maxLines = 1,
      TextInputType? keyboard,
      String? Function(String?)? validator,
      String? forceErrorText,
      ValueChanged<String>? onChanged,
    }) => Padding(
      padding: const EdgeInsets.symmetric(vertical: DashSpace.sm),
      child: TextFormField(
        controller: _c[key],
        style: t.body,
        maxLength: maxLength,
        maxLines: maxLines,
        keyboardType: keyboard,
        decoration: dashDecoration(t, labelText: label),
        validator: validator,
        forceErrorText: forceErrorText,
        onChanged: onChanged,
      ).tagged(_fieldTag(key, area: 'supplier_form')),
    );

    return logTag(
      'sheet.supplier_form',
      DraggableSheetSurface(
        initialSize: 0.75,
        minSize: 0.4,
        builder: (context, controller) => Form(
          key: _formKey,
          child: ListView(
            controller: controller,
            padding: EdgeInsets.fromLTRB(
              DashSpace.gutter,
              0,
              DashSpace.gutter,
              DashSpace.xl + bottomInset,
            ),
            children: [
              Text(
                widget.existing == null
                    ? l10n.inventorySupplierNew
                    : l10n.inventorySupplierEdit,
                style: t.display,
              ),
              const SizedBox(height: DashSpace.md),
              field(
                'name',
                '${l10n.inventorySupplierFieldName} *',
                maxLength: SupplierDraft.maxName,
                validator: (v) => _validateName(l10n, v),
                forceErrorText: _nameTaken
                    ? l10n.inventorySupplierNameTaken
                    : null,
                onChanged: (_) {
                  if (_nameTaken) setState(() => _nameTaken = false);
                },
              ),
              field(
                'website',
                l10n.inventorySupplierFieldWebsite,
                maxLength: SupplierDraft.maxWebsite,
                keyboard: TextInputType.url,
              ),
              field(
                'customerNumber',
                l10n.inventorySupplierFieldCustomerNumber,
                maxLength: SupplierDraft.maxCustomerNumber,
              ),
              field(
                'note',
                l10n.inventoryFieldNote,
                maxLength: SupplierDraft.maxNote,
                maxLines: 3,
              ),
              const SizedBox(height: DashSpace.lg),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: t.accentGreen,
                    foregroundColor: _onAccentGreen,
                    padding: const EdgeInsets.symmetric(vertical: DashSpace.lg),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? DashSpinner(size: 20, color: _onAccentGreen)
                      : Text(l10n.inventorySave),
                ).tagged('supplier_form.save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
