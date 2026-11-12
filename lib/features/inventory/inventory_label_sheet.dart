part of 'inventory_screen.dart';

/// Custom label sheets (server #3296): the one-off form, and the pieces the
/// stock picker and the form share. A saved template is the same sheet under a
/// name, so everything here takes a [SheetLayout] and neither knows which it is.

/// A length in the reader's own decimal mark, at most two places.
String _mmLabel(AppLocalizations l10n, double mm) =>
    (NumberFormat.decimalPattern(
      l10n.localeName,
    )..maximumFractionDigits = 2).format(mm);

String _pageName(AppLocalizations l10n, LabelPageSize page) => switch (page) {
  LabelPageSize.a4 => l10n.labelSheetPageA4,
  LabelPageSize.letter => l10n.labelSheetPageLetter,
};

/// "A4 · 63.5 × 38.1 mm · 21 labels (3 × 7)", the line under a sheet's name.
String _sheetSummary(AppLocalizations l10n, SheetLayout layout) =>
    l10n.labelSheetSummary(
      _pageName(l10n, layout.page),
      _mmLabel(l10n, layout.labelWidthMm),
      _mmLabel(l10n, layout.labelHeightMm),
      layout.capacity,
      layout.columns,
      layout.rows,
    );

/// Why a sheet cannot be printed, in the form's own words. [layout] null is a
/// form with a field still empty or not a number.
String? _sheetProblemText(AppLocalizations l10n, SheetLayout? layout) {
  if (layout == null) return l10n.labelSheetIncomplete;
  final report = layout.problem;
  if (report == null) return null;
  return switch (report.problem) {
    SheetProblem.tooSmall => l10n.labelSheetTooSmall(
      minLabelWidthMm.round(),
      minLabelHeightMm.round(),
    ),
    SheetProblem.tooLong => l10n.labelSheetTooLong(maxSheetLengthMm.round()),
    SheetProblem.columns => l10n.labelSheetColumnsRange(maxSheetColumns),
    SheetProblem.rows => l10n.labelSheetRowsRange(maxSheetRows),
    SheetProblem.negative => l10n.labelSheetNegative,
    SheetProblem.tooWide => l10n.labelSheetTooWide(
      _mmLabel(l10n, report.sizeMm),
      _mmLabel(l10n, report.pageMm),
    ),
    SheetProblem.tooTall => l10n.labelSheetTooTall(
      _mmLabel(l10n, report.sizeMm),
      _mmLabel(l10n, report.pageMm),
    ),
  };
}

/// Step 2b of label printing: a sheet of the user's own measures. Closed with
/// "Use this sheet" it hands back the [LabelStock] to print on; closed any other
/// way it cancels, like every step before it.
class _CustomSheetForm extends ConsumerStatefulWidget {
  const _CustomSheetForm({required this.initial, this.existing});

  /// What the form opens with: the sheet last used, or the web form's own
  /// starting point — or the saved template's, when [existing] is edited.
  final SheetLayout initial;

  /// A saved template being edited, or null for a one-off sheet. Saving a
  /// one-off sheet makes the form edit the template it just created.
  final SavedLabelTemplate? existing;

  @override
  ConsumerState<_CustomSheetForm> createState() => _CustomSheetFormState();
}

class _CustomSheetFormState extends ConsumerState<_CustomSheetForm> {
  late SavedLabelTemplate? _saved = widget.existing;
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  bool _saving = false;

  /// A 409 from the save, shown on the name field until the name is edited.
  bool _nameTaken = false;

  late final _start = SheetLayoutDraft.fromLayout(widget.initial);
  late var _page = _start.page;
  late final _width = TextEditingController(text: _start.labelWidth);
  late final _height = TextEditingController(text: _start.labelHeight);
  late final _columns = TextEditingController(text: _start.columns);
  late final _rows = TextEditingController(text: _start.rows);
  late final _top = TextEditingController(text: _start.top);
  late final _left = TextEditingController(text: _start.left);
  late final _columnGap = TextEditingController(text: _start.columnGap);
  late final _rowGap = TextEditingController(text: _start.rowGap);

  @override
  void dispose() {
    for (final c in [
      _name,
      _width,
      _height,
      _columns,
      _rows,
      _top,
      _left,
      _columnGap,
      _rowGap,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  SheetLayout? get _layout => SheetLayoutDraft(
    page: _page,
    labelWidth: _width.text,
    labelHeight: _height.text,
    columns: _columns.text,
    rows: _rows.text,
    top: _top.text,
    left: _left.text,
    columnGap: _columnGap.text,
    rowGap: _rowGap.text,
  ).layout;

  /// Saves the sheet on the server: a new template, or the one being edited
  /// replaced as a whole. The form stays open, so the sheet can be used right
  /// after, and a new template becomes the one the form edits.
  Future<void> _save() async {
    final layout = _layout;
    final name = _name.text.trim();
    if (layout == null || layout.problem != null || name.isEmpty) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(labelTemplatesRepositoryProvider);
    final container = ProviderScope.containerOf(context);
    final existing = _saved;
    setState(() => _saving = true);
    try {
      final saved = existing == null
          ? await repo.create(name, layout)
          : await repo.update(existing.id, name, layout);
      if (!mounted) return;
      setState(() {
        _saved = saved;
        _saving = false;
        _nameTaken = false;
      });
      messenger.snack(l10n.labelSheetSaved(saved.name));
    } on AppApiException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _nameTaken = e.statusCode == 409;
          // The template being edited is gone (someone else deleted it): what
          // is typed is now a new template, and saving it again must not
          // replace a row that no longer exists.
          if (existing != null && e.statusCode == 404) _saved = null;
        });
      }
      if (e.statusCode != 409) {
        showApiFailure(
          mounted ? messenger : null,
          e,
          l10n,
          action: 'label_sheet.save',
        );
      }
    } catch (_) {
      if (mounted) setState(() => _saving = false);
      rethrow;
    } finally {
      // Also after a refusal: a 404 is a template someone else deleted, and
      // the list behind this sheet should say so.
      container.invalidate(labelTemplatesProvider);
    }
  }

  Future<void> _delete() async {
    final saved = _saved;
    if (saved == null) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await confirmDialog(
      context,
      id: 'label_sheet.delete_confirm',
      title: l10n.labelSheetDeleteTitle(saved.name),
      message: l10n.labelSheetDeleteBody,
      confirmLabel: l10n.inventoryDelete,
      destructive: true,
    );
    if (!ok || !mounted) return;
    final repo = ref.read(labelTemplatesRepositoryProvider);
    final container = ProviderScope.containerOf(context);
    setState(() => _saving = true);
    try {
      await repo.delete(saved.id);
      messenger.snack(l10n.labelSheetDeleted(saved.name));
      if (mounted) Navigator.of(context).pop();
    } on AppApiException catch (e) {
      if (mounted) setState(() => _saving = false);
      if (e.statusCode == 404) {
        // Someone else deleted it first: what was asked for has happened.
        messenger.snack(l10n.labelSheetDeleted(saved.name));
        if (mounted) Navigator.of(context).pop();
        return;
      }
      showApiFailure(
        mounted ? messenger : null,
        e,
        l10n,
        action: 'label_sheet.delete',
      );
    } catch (_) {
      if (mounted) setState(() => _saving = false);
      rethrow;
    } finally {
      container.invalidate(labelTemplatesProvider);
    }
  }

  Widget _field(
    TextEditingController controller,
    String label,
    String id, {
    bool whole = false,
  }) {
    final t = DashTokens.of(context);
    return TextField(
      controller: controller,
      style: t.body,
      keyboardType: TextInputType.numberWithOptions(decimal: !whole),
      decoration: dashDecoration(t, labelText: label),
      onChanged: (_) => setState(() {}),
    ).tagged(id);
  }

  /// Two fields side by side, one under the other at large text, where a label
  /// would no longer fit the half of a phone.
  Widget _pair(Widget a, Widget b) => dashLargeText(context)
      ? Column(
          children: [
            a,
            const SizedBox(height: DashSpace.md),
            b,
          ],
        )
      : Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: a),
            const SizedBox(width: DashSpace.md),
            Expanded(child: b),
          ],
        );

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final layout = _layout;
    final problem = _sheetProblemText(l10n, layout);
    const gap = SizedBox(height: DashSpace.md);
    final canManage = ref.watch(
      permissionProvider(Permissions.inventoryUpdate),
    );
    final canSave =
        canManage &&
        !_saving &&
        problem == null &&
        _name.text.trim().isNotEmpty;

    return DraggableSheetSurface(
      initialSize: 0.9,
      minSize: 0.5,
      builder: (context, controller) => Column(
        children: [
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(
                DashSpace.gutter,
                0,
                DashSpace.gutter,
                DashSpace.md,
              ),
              children: [
                Text(l10n.labelSheetCustom, style: t.titleLg),
                const SizedBox(height: DashSpace.lg),
                if (canManage) ...[
                  TextField(
                    controller: _name,
                    style: t.body,
                    maxLength: maxLabelTemplateName,
                    decoration: dashDecoration(
                      t,
                      labelText: l10n.labelSheetName,
                      errorText: _nameTaken ? l10n.labelSheetNameTaken : null,
                    ).copyWith(counterText: ''),
                    onChanged: (_) => setState(() => _nameTaken = false),
                  ).tagged('label_sheet.name'),
                  gap,
                ],
                _ChipRow<LabelPageSize>(
                  id: 'label_sheet.page',
                  label: l10n.labelSheetPage,
                  options: {
                    for (final p in LabelPageSize.values) p: _pageName(l10n, p),
                  },
                  value: _page,
                  onChanged: (p) => setState(() => _page = p),
                ),
                gap,
                _pair(
                  _field(
                    _width,
                    l10n.labelSheetLabelWidth,
                    'label_sheet.label_width',
                  ),
                  _field(
                    _height,
                    l10n.labelSheetLabelHeight,
                    'label_sheet.label_height',
                  ),
                ),
                gap,
                _pair(
                  _field(
                    _columns,
                    l10n.labelSheetColumns,
                    'label_sheet.columns',
                    whole: true,
                  ),
                  _field(
                    _rows,
                    l10n.labelSheetRows,
                    'label_sheet.rows',
                    whole: true,
                  ),
                ),
                gap,
                _pair(
                  _field(_top, l10n.labelSheetTopMargin, 'label_sheet.top'),
                  _field(_left, l10n.labelSheetLeftMargin, 'label_sheet.left'),
                ),
                gap,
                _pair(
                  _field(
                    _columnGap,
                    l10n.labelSheetColumnGap,
                    'label_sheet.column_gap',
                  ),
                  _field(_rowGap, l10n.labelSheetRowGap, 'label_sheet.row_gap'),
                ),
                const SizedBox(height: DashSpace.lg),
                _SheetPreview(layout: layout, page: _page),
                const SizedBox(height: DashSpace.sm),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    problem ?? _sheetSummary(l10n, layout!),
                    style: t.labelSoft.legible.copyWith(
                      color: problem == null ? t.textSecondary : t.dangerInk,
                    ),
                  ),
                ),
                if (canManage) ...[
                  const SizedBox(height: DashSpace.lg),
                  OutlinedButton(
                    onPressed: canSave ? _save : null,
                    child: Text(
                      _saved == null
                          ? l10n.labelSheetSaveAs
                          : l10n.labelSheetSaveChanges,
                    ),
                  ).tagged('label_sheet.save'),
                  if (_saved != null) ...[
                    gap,
                    OutlinedButton(
                      onPressed: _saving ? null : _delete,
                      child: Text(l10n.labelSheetDelete),
                    ).tagged('label_sheet.delete'),
                  ],
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(
              DashSpace.gutter,
              DashSpace.sm,
              DashSpace.gutter,
              DashSpace.lg,
            ),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: t.subCardBorder)),
            ),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: problem != null || _saving
                    ? null
                    : () => Navigator.of(context).pop(
                        LabelStock(SpoolLabelTemplate.custom, layout: layout),
                      ),
                child: Text(l10n.labelSheetUse),
              ).tagged('label_sheet.use'),
            ),
          ),
        ],
      ),
    );
  }
}

/// The page with the label grid on it, to scale, so a layout that runs off the
/// edge is seen before it is read: a label that does not fit is drawn red.
/// Nothing is drawn for a form with a field still empty.
class _SheetPreview extends StatelessWidget {
  const _SheetPreview({required this.layout, required this.page});

  final SheetLayout? layout;
  final LabelPageSize page;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 240),
        child: AspectRatio(
          aspectRatio: page.widthMm / page.heightMm,
          child: Semantics(
            label: layout == null ? null : _sheetSummary(l10n, layout!),
            excludeSemantics: true,
            child: CustomPaint(
              painter: _SheetPainter(
                layout: layout,
                page: page,
                paper: t.subCard,
                edge: t.subCardBorder,
                fits: t.accentGreenInk,
                overflows: t.dangerInk,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetPainter extends CustomPainter {
  _SheetPainter({
    required this.layout,
    required this.page,
    required this.paper,
    required this.edge,
    required this.fits,
    required this.overflows,
  });

  final SheetLayout? layout;
  final LabelPageSize page;
  final Color paper;
  final Color edge;
  final Color fits;
  final Color overflows;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / page.widthMm;
    final outline = Offset.zero & size;
    canvas
      ..drawRect(outline, Paint()..color = paper)
      ..drawRect(
        outline,
        Paint()
          ..color = edge
          ..style = PaintingStyle.stroke,
      );
    final l = layout;
    // A grid the server would refuse outright (a 300 mm label, 4000 rows) would
    // paint thousands of rectangles off the page: the numbers are what the
    // message below names, not the picture.
    if (l == null || !l.gridIsDrawable) return;
    final cell = Paint()..style = PaintingStyle.stroke;
    for (var row = 0; row < l.rows; row++) {
      for (var col = 0; col < l.columns; col++) {
        final left = l.leftMm + col * (l.labelWidthMm + l.columnGapMm);
        final top = l.topMm + row * (l.labelHeightMm + l.rowGapMm);
        final runsOff =
            left + l.labelWidthMm > page.widthMm + 0.01 ||
            top + l.labelHeightMm > page.heightMm + 0.01;
        cell.color = runsOff ? overflows : fits;
        canvas.drawRect(
          Rect.fromLTWH(
            left * scale,
            top * scale,
            l.labelWidthMm * scale,
            l.labelHeightMm * scale,
          ),
          cell,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_SheetPainter old) =>
      old.layout != layout || old.page != page || old.paper != paper;
}
