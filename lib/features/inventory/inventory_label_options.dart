part of 'inventory_screen.dart';

/// Step 3 of label printing: what goes on the label and where the file goes.
///
/// Every control writes straight to [labelPrintPrefsProvider], so the sheet
/// opens next time as it was left; "Print" closes it with the destination it
/// showed, so what the caller does is what the user saw. The chosen lines are
/// kept per [template] — a small label has room for less than
/// a large one.
class _LabelOptionsSheet extends ConsumerWidget {
  const _LabelOptionsSheet({required this.template});

  final SpoolLabelTemplate template;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final prefs = ref.watch(labelPrintPrefsProvider);
    // An older server answers a PDF with the default lines whatever it was
    // asked, so what it cannot do is not offered.
    final canChoose = ref.watch(labelFieldsProvider).orFalse;
    final printerSet = ref.watch(labelPrinterUrlProvider) != null;
    final png = canChoose && prefs.format == SpoolLabelFormat.png;
    // Unknown while `/info` is out, and then not "fits": the default stays the
    // print dialog until the printer has said which stock it holds.
    final printerFits =
        ref.watch(labelPrinterInfoProvider).valueOrNull?.takes(template) ??
        false;
    final destination = prefs.resolveDestination(
      printerSet: printerSet,
      printerFits: printerFits,
      png: png,
    );
    void update(LabelPrintPrefs next) =>
        ref.read(labelPrintPrefsProvider.notifier).set(next);

    final fields = prefs.fieldsFor(template);
    void toggle(SpoolLabelField field, bool on) => update(
      prefs.copyWith(
        fields: {
          ...prefs.fields,
          template: on ? {...fields, field} : ({...fields}..remove(field)),
        },
      ),
    );

    // Two columns in the web picker's order; an odd one out sits left.
    const all = SpoolLabelField.values;
    final half = (all.length / 2).ceil();

    return DraggableSheetSurface(
      initialSize: 0.85,
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
                Text(l10n.labelOptionsTitle, style: t.titleLg),
                if (canChoose) ...[
                  const SizedBox(height: DashSpace.lg),
                  Row(
                    children: [
                      Expanded(
                        child: Text(l10n.labelFieldsTitle, style: t.bodyBold),
                      ),
                      _TextAction(
                        label: l10n.labelFieldsReset,
                        onPressed: setEquals(fields, SpoolLabelField.defaults)
                            ? null
                            : () => update(
                                prefs.copyWith(
                                  fields: {...prefs.fields}..remove(template),
                                ),
                              ),
                      ),
                    ],
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final column in [
                        all.sublist(0, half),
                        all.sublist(half),
                      ])
                        Expanded(
                          child: Column(
                            children: [
                              for (final field in column)
                                _CheckRow(
                                  id: 'label_options.field',
                                  value: fields.contains(field),
                                  onChanged: (on) => toggle(field, on),
                                  label: _labelFieldName(l10n, field),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
                _CheckRow(
                  id: 'label_options.monochrome',
                  value: prefs.monochrome,
                  onChanged: (v) => update(prefs.copyWith(monochrome: v)),
                  label: l10n.inventoryLabelsMonochrome,
                  hint: l10n.inventoryLabelsMonochromeHint,
                ),
                const SizedBox(height: DashSpace.md),
                if (canChoose) ...[
                  _ChipRow(
                    label: l10n.labelFormatTitle,
                    options: const {
                      SpoolLabelFormat.pdf: 'PDF',
                      SpoolLabelFormat.png: 'PNG',
                    },
                    value: prefs.format,
                    onChanged: (v) => update(prefs.copyWith(format: v)),
                  ),
                  if (png) ...[
                    const SizedBox(height: DashSpace.sm),
                    _ChipRow(
                      label: l10n.labelDpiTitle,
                      options: {
                        for (final d in spoolLabelDpiChoices) d: '$d dpi',
                      },
                      value: prefs.dpi,
                      onChanged: (v) => update(prefs.copyWith(dpi: v)),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: DashSpace.xs),
                      child: Text(
                        l10n.labelFormatPngHint,
                        style: t.microSoft.legible,
                      ),
                    ),
                  ],
                  const SizedBox(height: DashSpace.md),
                ],
                _ChipRow(
                  label: l10n.labelSendToTitle,
                  options: {
                    if (!png) LabelDestination.system: l10n.labelSendSystem,
                    LabelDestination.share: l10n.labelSendShare,
                    LabelDestination.save: l10n.labelSendSave,
                    if (!png && printerSet)
                      LabelDestination.labelPrinter: l10n.labelSendPrinter,
                  },
                  value: destination,
                  onChanged: (v) => update(prefs.copyWith(destination: v)),
                ),
                if (!png && !printerSet) _SetUpLabelPrinterRow(),
                if (destination == LabelDestination.labelPrinter)
                  ..._printerOptions(context, l10n, prefs, update),
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
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(destination),
                icon: Icon(switch (destination) {
                  LabelDestination.system ||
                  LabelDestination.labelPrinter => Icons.print_outlined,
                  LabelDestination.share => Icons.ios_share,
                  LabelDestination.save => Icons.save_alt,
                }, size: 18),
                label: Text(l10n.inventoryLabelsPrint),
              ).tagged('label_options.print'),
            ),
          ),
        ],
      ),
    );
  }

  /// The print server's own job options: copies, and where the cutter fires.
  List<Widget> _printerOptions(
    BuildContext context,
    AppLocalizations l10n,
    LabelPrintPrefs prefs,
    ValueChanged<LabelPrintPrefs> update,
  ) {
    final t = DashTokens.of(context);
    return [
      const SizedBox(height: DashSpace.md),
      Row(
        children: [
          Expanded(child: Text(l10n.labelPrinterCopies, style: t.body)),
          DashStepper(
            value: prefs.copies,
            min: 1,
            max: labelPrinterMaxCopies,
            onChanged: (v) => update(prefs.copyWith(copies: v)),
            lessTooltip: l10n.copiesLess,
            moreTooltip: l10n.copiesMore,
            lessId: 'label_options.copies_down',
            moreId: 'label_options.copies_up',
          ),
        ],
      ),
      _CheckRow(
        id: 'label_options.cut_at_end',
        value: prefs.cutAtEnd,
        onChanged: (v) => update(prefs.copyWith(cutAtEnd: v)),
        label: l10n.labelPrinterCutAtEnd,
      ),
      Row(
        children: [
          Expanded(child: Text(l10n.labelPrinterCutEvery, style: t.body)),
          DashStepper(
            value: prefs.cutEvery,
            min: 0,
            max: maxSpoolLabelsPerRequest,
            onChanged: (v) => update(prefs.copyWith(cutEvery: v)),
            lessTooltip: l10n.labelCutEveryLess,
            moreTooltip: l10n.labelCutEveryMore,
            lessId: 'label_options.cut_every_down',
            moreId: 'label_options.cut_every_up',
          ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.only(top: DashSpace.xs),
        child: Text(l10n.labelPrinterCutEveryHint, style: t.microSoft.legible),
      ),
    ];
  }
}

/// Shown instead of the "Label printer" choice while none is set up, so the
/// option is discoverable by someone who never opens the settings.
class _SetUpLabelPrinterRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => context.push('/settings/label-printer'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: DashSpace.sm),
        child: Row(
          children: [
            Icon(Icons.label_outline, size: 20, color: t.textTertiary),
            const SizedBox(width: DashSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.labelPrinterSetUp, style: t.body),
                  Text(l10n.labelPrinterSetUpHint, style: t.microSoft.legible),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: t.textTertiary),
          ],
        ),
      ),
    ).tagged('labels.set_up_label_printer');
  }
}

String _labelFieldName(AppLocalizations l10n, SpoolLabelField field) =>
    switch (field) {
      SpoolLabelField.brand => l10n.labelFieldBrand,
      SpoolLabelField.material => l10n.labelFieldMaterial,
      SpoolLabelField.hex => l10n.labelFieldHex,
      SpoolLabelField.name => l10n.labelFieldName,
      SpoolLabelField.location => l10n.labelFieldLocation,
      SpoolLabelField.materialNumber => l10n.labelFieldMaterialNumber,
      SpoolLabelField.temps => l10n.labelFieldTemps,
      SpoolLabelField.weight => l10n.labelFieldWeight,
      SpoolLabelField.note => l10n.labelFieldNote,
      SpoolLabelField.added => l10n.labelFieldAdded,
      SpoolLabelField.qr => l10n.labelFieldQr,
      SpoolLabelField.spoolId => l10n.labelFieldSpoolId,
    };
