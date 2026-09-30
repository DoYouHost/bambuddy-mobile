part of 'inventory_screen.dart';

/// One supplier assignment as the spool form edits it.
class _LinkDraft {
  _LinkDraft(SpoolSupplierLink link, {bool keepPurchaseSource = true})
    : supplierId = link.supplierId,
      supplierName = link.supplierName,
      isPurchaseSource = keepPurchaseSource && link.isPurchaseSource,
      article = TextEditingController(text: link.articleNumber ?? ''),
      price = TextEditingController(
        text: link.quotedPricePerKg?.toStringAsFixed(2) ?? '',
      );

  final int supplierId;
  final String supplierName;
  bool isPurchaseSource;
  final TextEditingController article;
  final TextEditingController price;

  SpoolSupplierLink toLink() {
    final number = article.text.trim();
    return SpoolSupplierLink(
      supplierId: supplierId,
      supplierName: supplierName,
      articleNumber: number.isEmpty ? null : number,
      quotedPricePerKg: parseUserDecimal(price.text),
      isPurchaseSource: isPurchaseSource,
    );
  }

  void dispose() {
    article.dispose();
    price.dispose();
  }
}

/// Where this spool's product can be bought, and which of those places this
/// spool came from. Every change goes through [onChanged], which is what marks
/// the list for writing — an untouched section on a new spool writes nothing,
/// so the server can fill it in from another spool of the same product.
class _SupplierLinksSection extends ConsumerWidget {
  const _SupplierLinksSection({required this.links, required this.onChanged});

  final List<_LinkDraft> links;

  /// Runs [change] inside the form's `setState` and marks the list dirty.
  final void Function(VoidCallback change) onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: DashSpace.sm),
        _FormSection(label: l10n.inventorySuppliersTitle),
        InlineNote(
          l10n.inventorySupplierLinksHint,
          icon: Icons.info_outline,
          padding: const EdgeInsets.only(bottom: DashSpace.xs),
        ),
        for (final link in links) _linkCard(context, l10n, link),
        const SizedBox(height: DashSpace.sm),
        // Full width, so it lines up with the cards above it — a text button's
        // own padding left it indented against them.
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          onPressed: () => _pick(context),
          icon: const Icon(Icons.add_business_outlined),
          label: Text(l10n.inventorySupplierAssign),
        ).tagged('spool_form.supplier_add'),
      ],
    );
  }

  Future<void> _pick(BuildContext context) async {
    final taken = {for (final l in links) l.supplierId};
    final picked = await dashSurfaceSheet<Supplier>(
      context,
      builder: (_) => _SupplierPickerSheet(taken: taken),
    );
    if (picked == null || taken.contains(picked.id)) return;
    onChanged(
      () => links.add(
        _LinkDraft(
          SpoolSupplierLink(
            supplierId: picked.id,
            supplierName: picked.name,
            // The first one in is most likely where the spool came from; the
            // chip is one tap to move if not.
            isPurchaseSource: links.isEmpty,
          ),
        ),
      ),
    );
  }

  Widget _linkCard(
    BuildContext context,
    AppLocalizations l10n,
    _LinkDraft link,
  ) {
    final t = DashTokens.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: DashSpace.sm),
      // The close button's 48 dp touch box draws its 24 dp icon 12 dp in, so
      // the card gives it xs on the right and the fields below take md more:
      // the icon's edge and the fields' edge then both sit lg from the border.
      padding: const EdgeInsets.fromLTRB(
        DashSpace.lg,
        DashSpace.xs,
        DashSpace.xs,
        DashSpace.lg,
      ),
      decoration: BoxDecoration(
        color: t.subCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: link.isPurchaseSource
              ? t.accentGreen.withValues(alpha: 0.5)
              : t.subCardBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  link.supplierName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.titleSm,
                ),
              ),
              FilterChip(
                label: Text(l10n.inventorySupplierBoughtHere),
                selected: link.isPurchaseSource,
                // One purchase source per spool, or the replace is a 400.
                onSelected: (on) => onChanged(() {
                  for (final other in links) {
                    other.isPurchaseSource = on && identical(other, link);
                  }
                }),
              ).tagged('spool_form.supplier_bought_here'),
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: l10n.inventorySupplierUnassign,
                onPressed: () => onChanged(() {
                  links.remove(link);
                  link.dispose();
                }),
              ).tagged('spool_form.supplier_remove'),
            ],
          ),
          const SizedBox(height: DashSpace.xs),
          Padding(
            padding: const EdgeInsets.only(right: DashSpace.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: link.article,
                    style: t.body,
                    maxLength: SpoolSupplierLink.maxArticleNumber,
                    decoration: dashDecoration(
                      t,
                      labelText: l10n.inventorySupplierFieldArticle,
                    ).copyWith(counterText: ''),
                    onChanged: (_) => onChanged(() {}),
                  ).tagged('spool_form.supplier_article'),
                ),
                const SizedBox(width: DashSpace.md),
                Expanded(
                  child: TextFormField(
                    controller: link.price,
                    style: t.body,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: dashDecoration(
                      t,
                      labelText: l10n.inventorySupplierFieldQuotedPrice,
                    ),
                    validator: (v) {
                      final text = (v ?? '').trim();
                      if (text.isEmpty) return null;
                      final value = parseUserDecimal(text);
                      if (value == null) {
                        return l10n.inventoryFieldInvalidNumber;
                      }
                      if (value < 0) return l10n.inventoryFieldNegative;
                      return null;
                    },
                    onChanged: (_) => onChanged(() {}),
                  ).tagged('spool_form.supplier_price'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The master list minus what the spool already has, plus a way to add a
/// supplier that is not on it yet without leaving the spool form.
class _SupplierPickerSheet extends ConsumerWidget {
  const _SupplierPickerSheet({required this.taken});

  final Set<int> taken;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final list = ref.watch(supplierListProvider);
    final available = [
      for (final s in list.valueOrNull ?? const <Supplier>[])
        if (!taken.contains(s.id)) s,
    ];

    return logTag(
      'sheet.supplier_picker',
      DraggableSheetSurface(
        initialSize: 0.5,
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
            Text(
              l10n.inventorySupplierAssign,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: DashSpace.sm),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.add),
              title: Text(l10n.inventorySupplierNew),
              onTap: () async {
                final navigator = Navigator.of(context);
                final created = await _openSupplierForm(context);
                if (created != null) navigator.pop(created);
              },
            ).tagged('supplier_picker.new'),
            if (list.isLoading && !list.hasValue)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: DashSpace.lg),
                child: DashLoading(),
              )
            else if (available.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: DashSpace.md),
                child: Text(
                  list.hasError
                      ? l10n.inventorySuppliersLoadFailed
                      : l10n.inventorySupplierNoneLeft,
                  style: t.bodyPlain.copyWith(color: t.textSecondary),
                ),
              )
            else
              for (final supplier in available)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.storefront_outlined),
                  title: Text(supplier.name),
                  onTap: () => Navigator.of(context).pop(supplier),
                ).tagged('supplier_picker.option'),
          ],
        ),
      ),
    );
  }
}
