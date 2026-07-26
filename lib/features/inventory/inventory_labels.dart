part of 'inventory_screen.dart';

/// Spool label printing, mirroring bambuddy's web label modal.
///
/// Two steps, because six template cards plus a spool list don't fit one phone
/// sheet: pick spools here, then pick the label stock in [_TemplateSheet]. The
/// server renders the PDF; [Printing] hands it to the platform print dialog
/// (which also offers "Save as PDF") or to the share sheet.
class _LabelSheet extends ConsumerStatefulWidget {
  const _LabelSheet({required this.spools, required this.initialSelected});

  /// Spools the sheet may choose from — the screen's current filter result, so
  /// the sheet stays consistent with what the user sees behind it.
  final List<Spool> spools;

  /// Ids checked on open. Selection mode passes the picked spools; the app
  /// bar's "print for all" passes every visible id.
  final Set<int> initialSelected;

  @override
  ConsumerState<_LabelSheet> createState() => _LabelSheetState();
}

enum _LabelSort { id, color }

class _LabelSheetState extends ConsumerState<_LabelSheet> {
  late final Set<int> _selected = {...widget.initialSelected};
  String _query = '';
  String? _material;
  var _sort = _LabelSort.id;
  bool _monochrome = false;
  bool _share = false;
  bool _busy = false;

  /// Spools in print order. The backend prints labels in the order it receives
  /// ids, so sorting here is what makes "by colour" reach the sheet.
  List<Spool> get _sorted {
    final list = [...widget.spools];
    if (_sort == _LabelSort.color) {
      list.sort((a, b) {
        final ka = spoolColorSortKey(parseSpoolColor(a.rgba));
        final kb = spoolColorSortKey(parseSpoolColor(b.rgba));
        final byBucket = ka.bucket.compareTo(kb.bucket);
        if (byBucket != 0) return byBucket;
        final byPos = ka.pos.compareTo(kb.pos);
        // Stable tiebreak on id so equal colours print deterministically.
        return byPos != 0 ? byPos : a.id.compareTo(b.id);
      });
    } else {
      list.sort((a, b) => a.id.compareTo(b.id));
    }
    return list;
  }

  List<Spool> get _visible {
    final q = _query.trim().toLowerCase();
    return [
      for (final s in _sorted)
        if (_material == null || s.material.toUpperCase() == _material)
          if (q.isEmpty || _labelSearchText(s).contains(q)) s,
    ];
  }

  /// Material chips come from the full pool, not the visible slice, so they
  /// don't disappear as the search narrows.
  List<String> get _materials {
    final set = <String>{
      for (final s in widget.spools)
        if (s.material.trim().isNotEmpty) s.material.toUpperCase(),
    };
    final list = set.toList()..sort();
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final visible = _visible;
    final allVisibleChecked =
        visible.isNotEmpty && visible.every((s) => _selected.contains(s.id));

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (context, controller) => _SheetSurface(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.print_outlined,
                        size: 20,
                        color: t.accentGreenInk,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.inventoryLabelsTitle,
                          style: TextStyle(
                            fontFamily: DashTokens.fontUi,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: t.textPrimary,
                          ),
                        ),
                      ),
                      Text(
                        l10n.inventorySelectedCount(_selected.length),
                        style: TextStyle(
                          fontFamily: DashTokens.fontMono,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: t.textTertiary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DashSearchField(
                    id: 'spool_labels.search',
                    hintText: l10n.inventoryLabelsSearchHint,
                    onChanged: (v) => setState(() => _query = v),
                  ),
                  const SizedBox(height: 10),
                  if (_materials.length > 1) ...[
                    _ChipRow(
                      label: l10n.inventoryLabelsMaterial,
                      options: {
                        null: l10n.inventoryLabelsAllMaterials,
                        for (final m in _materials) m: m,
                      },
                      value: _material,
                      onChanged: (v) => setState(() => _material = v),
                    ),
                    const SizedBox(height: 6),
                  ],
                  _ChipRow(
                    label: l10n.inventoryLabelsSort,
                    options: {
                      _LabelSort.id: l10n.inventoryLabelsSortById,
                      _LabelSort.color: l10n.inventoryLabelsSortByColor,
                    },
                    value: _sort,
                    onChanged: (v) => setState(() => _sort = v),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.inventoryLabelsPickSpools,
                          style: TextStyle(
                            fontFamily: DashTokens.fontUi,
                            fontSize: 12.5,
                            color: t.textSecondary,
                          ),
                        ),
                      ),
                      _TextAction(
                        label: allVisibleChecked
                            ? l10n.inventoryLabelsDeselectVisible
                            : l10n.inventoryLabelsSelectVisible,
                        onPressed: visible.isEmpty
                            ? null
                            : () => setState(() {
                                final ids = visible.map((s) => s.id);
                                if (allVisibleChecked) {
                                  _selected.removeAll(ids);
                                } else {
                                  _selected.addAll(ids);
                                }
                              }),
                      ),
                      const SizedBox(width: 12),
                      _TextAction(
                        label: l10n.inventoryLabelsClearAll,
                        muted: true,
                        onPressed: _selected.isEmpty
                            ? null
                            : () => setState(_selected.clear),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            Expanded(
              child: visible.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          l10n.inventoryLabelsNoMatches,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: DashTokens.fontUi,
                            fontSize: 13,
                            color: t.textTertiary,
                          ),
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: controller,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemCount: visible.length,
                      itemBuilder: (context, i) {
                        final spool = visible[i];
                        return _LabelSpoolRow(
                          spool: spool,
                          checked: _selected.contains(spool.id),
                          onTap: () => setState(() {
                            if (!_selected.remove(spool.id)) {
                              _selected.add(spool.id);
                            }
                          }),
                        );
                      },
                    ),
            ),

            _LabelFooter(
              monochrome: _monochrome,
              share: _share,
              busy: _busy,
              count: _selected.length,
              onMonochrome: (v) => setState(() => _monochrome = v),
              onShare: (v) => setState(() => _share = v),
              onPrint: _selected.isEmpty || _busy ? null : _pickTemplate,
            ),
          ],
        ),
      ),
    );
  }

  /// Step 2: pick the label stock, then render and hand off the PDF.
  Future<void> _pickTemplate() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);

    if (_selected.length > maxSpoolLabelsPerRequest) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            l10n.inventoryLabelsTooMany(maxSpoolLabelsPerRequest),
          ),
        ),
      );
      return;
    }

    final template = await showModalBottomSheet<SpoolLabelTemplate>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: _sheetBarrier,
      builder: (_) => const _TemplateSheet(),
    );
    if (template == null || !mounted) return;

    // Keep the sorted order — that's what makes "by colour" flow into an
    // Avery sheet instead of being re-sorted by id server-side.
    final ids = [
      for (final s in _sorted)
        if (_selected.contains(s.id)) s.id,
    ];

    setState(() => _busy = true);
    try {
      final pdf = await ref
          .read(inventoryRepositoryProvider)
          .renderLabels(ids, template, monochrome: _monochrome);
      if (!mounted) return;
      Navigator.of(context).pop();
      final filename = 'bambuddy-labels-${template.wire}.pdf';
      if (_share) {
        await Printing.sharePdf(bytes: pdf, filename: filename);
      } else {
        await Printing.layoutPdf(
          onLayout: (_) => pdf,
          name: filename,
          // Label stock is a fixed physical size — reflowing it to the
          // printer's page would defeat the whole point of the template.
          dynamicLayout: false,
        );
      }
    } on AppApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(e.localized(l10n))));
    } on Object {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.inventoryLabelsFailed)),
      );
    }
  }
}

/// Haystack the label search matches against.
String _labelSearchText(Spool s) => [
  s.colorName,
  s.material,
  s.subtype,
  s.brand,
  '#${s.id}',
].whereType<String>().join(' ').toLowerCase();

/// One checkable spool row in the label sheet.
class _LabelSpoolRow extends StatelessWidget {
  const _LabelSpoolRow({
    required this.spool,
    required this.checked,
    required this.onTap,
  });

  final Spool spool;
  final bool checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final name = [
      spool.colorName ??
          [spool.material, spool.subtype].whereType<String>().join(' '),
      if (spool.brand != null) spool.brand,
    ].whereType<String>().join(' · ');

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            Icon(
              checked ? Icons.check_box : Icons.check_box_outline_blank,
              size: 20,
              color: checked ? t.accentGreenInk : t.textTertiary,
            ),
            const SizedBox(width: 10),
            SpoolSwatch(rgba: spool.rgba, size: 20, radius: 6),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: DashTokens.fontUi,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: t.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '#${spool.id}',
              style: TextStyle(
                fontFamily: DashTokens.fontMono,
                fontSize: 11.5,
                color: t.textTertiary,
              ),
            ),
          ],
        ),
      ),
    ).tagged('labels.spool');
  }
}

/// Pinned bottom of the label sheet: print options plus the primary action.
class _LabelFooter extends StatelessWidget {
  const _LabelFooter({
    required this.monochrome,
    required this.share,
    required this.busy,
    required this.count,
    required this.onMonochrome,
    required this.onShare,
    required this.onPrint,
  });

  final bool monochrome;
  final bool share;
  final bool busy;
  final int count;
  final ValueChanged<bool> onMonochrome;
  final ValueChanged<bool> onShare;
  final VoidCallback? onPrint;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        16 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.subCardBorder)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CheckRow(
            value: monochrome,
            onChanged: onMonochrome,
            label: l10n.inventoryLabelsMonochrome,
            hint: l10n.inventoryLabelsMonochromeHint,
          ),
          _CheckRow(
            value: share,
            onChanged: onShare,
            label: l10n.inventoryLabelsShare,
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: t.accentGreen,
                foregroundColor: _onAccentGreen,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              onPressed: onPrint,
              icon: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _onAccentGreen,
                      ),
                    )
                  : Icon(share ? Icons.ios_share : Icons.print_outlined,
                      size: 18),
              label: Text(
                '${l10n.inventoryLabelsPrint} ($count)',
                style: const TextStyle(
                  fontFamily: DashTokens.fontUi,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ).tagged('labels.print'),
          ),
        ],
      ),
    );
  }
}

/// Step 2 of label printing: the six label stocks the server can render.
class _TemplateSheet extends StatelessWidget {
  const _TemplateSheet();

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final options = <(SpoolLabelTemplate, String, String)>[
      (
        SpoolLabelTemplate.amsHolderSmall,
        l10n.inventoryLabelsAmsSmall,
        l10n.inventoryLabelsAmsSmallHint,
      ),
      (
        SpoolLabelTemplate.amsHolderLarge,
        l10n.inventoryLabelsAmsLarge,
        l10n.inventoryLabelsAmsLargeHint,
      ),
      (
        SpoolLabelTemplate.box40x30,
        l10n.inventoryLabelsBox40,
        l10n.inventoryLabelsBox40Hint,
      ),
      (
        SpoolLabelTemplate.box62x29,
        l10n.inventoryLabelsBox62,
        l10n.inventoryLabelsBox62Hint,
      ),
      (
        SpoolLabelTemplate.averyL7160,
        l10n.inventoryLabelsAveryL7160,
        l10n.inventoryLabelsAveryL7160Hint,
      ),
      (
        SpoolLabelTemplate.avery5160,
        l10n.inventoryLabelsAvery5160,
        l10n.inventoryLabelsAvery5160Hint,
      ),
    ];

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (context, controller) => _SheetSurface(
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text(
              l10n.inventoryLabelsPickTemplate,
              style: TextStyle(
                fontFamily: DashTokens.fontUi,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: t.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            for (final (template, label, hint) in options)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: t.subCard,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => Navigator.of(context).pop(template),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: t.subCardBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: TextStyle(
                              fontFamily: DashTokens.fontUi,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: t.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            hint,
                            style: TextStyle(
                              fontFamily: DashTokens.fontUi,
                              fontSize: 12,
                              color: t.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ).tagged('labels.template'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Labelled row of single-choice chips (material filter, sort mode).
class _ChipRow<T> extends StatelessWidget {
  const _ChipRow({
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final Map<T, String> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: DashTokens.fontUi,
            fontSize: 11.5,
            color: t.textTertiary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final e in options.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _MiniChip(
                      label: e.value,
                      selected: e.key == value,
                      onTap: () => onChanged(e.key),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Material(
      color: selected ? t.accentGreen.withValues(alpha: 0.18) : t.subCard,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? t.accentGreen.withValues(alpha: 0.6)
                  : t.subCardBorder,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: DashTokens.fontUi,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: selected ? t.accentGreenInk : t.textSecondary,
            ),
          ),
        ),
      ).tagged('labels.chip'),
    );
  }
}

/// Inline text button used for the sheet's select/clear links.
class _TextAction extends StatelessWidget {
  const _TextAction({
    required this.label,
    required this.onPressed,
    this.muted = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final color = muted ? t.textSecondary : t.accentGreenInk;
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: DashTokens.fontUi,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: onPressed == null ? color.withValues(alpha: 0.4) : color,
          ),
        ),
      ),
    ).tagged('labels.text_action');
  }
}

/// Checkbox row with an optional secondary hint line.
class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.value,
    required this.onChanged,
    required this.label,
    this.hint,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              value ? Icons.check_box : Icons.check_box_outline_blank,
              size: 20,
              color: value ? t.accentGreenInk : t.textTertiary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily: DashTokens.fontUi,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: t.textPrimary,
                    ),
                  ),
                  if (hint != null)
                    Text(
                      hint!,
                      style: TextStyle(
                        fontFamily: DashTokens.fontUi,
                        fontSize: 11.5,
                        color: t.textTertiary,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ).tagged('labels.check');
  }
}
