part of 'printer_card.dart';

/// Which of a nozzle's figures a surface shows. The rack sheet shows all of
/// them. The section in a hotend's temperature sheet shows the four the
/// mock-up drew (diameter, flow, wear, print time): the sheet around it already
/// names the hotend and carries its status, and the type, rating, serial and
/// filament are one tap away on the rack for a printer that has one.
enum NozzleFigureSet { full, hotend }

/// What a nozzle reports about itself (#1908), as the web's hover card lists it
/// and in its order: diameter, type, flow, status, wear, print time, rating,
/// serial, filament. A figure the nozzle did not report is left out — older
/// firmware sends no print time, and "0h" would claim a nozzle that never
/// printed.
class NozzleFigures extends StatelessWidget {
  const NozzleFigures({
    super.key,
    required this.slot,
    this.set = NozzleFigureSet.full,
    this.status,
  });

  final NozzleRackSlot slot;
  final NozzleFigureSet set;

  /// The text of the status row, already worded for where the nozzle sits
  /// (docked, on the toolhead). Null leaves the row out.
  final String? status;

  @override
  Widget build(BuildContext context) {
    final rows = _nozzleRows(
      DashTokens.of(context),
      AppLocalizations.of(context),
      slot,
      set,
      status,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, row) in rows.indexed) ...[
          if (i > 0) const Divider(height: 1),
          row,
        ],
      ],
    );
  }
}

/// The rows [NozzleFigures] draws, empty when the nozzle reported none of them.
List<FactRow> _nozzleRows(
  DashTokens t,
  AppLocalizations l10n,
  NozzleRackSlot slot,
  NozzleFigureSet set,
  String? status,
) {
  final full = set == NozzleFigureSet.full;
  final diameter = nozzleDiameterLabel(slot.nozzleDiameter);
  final type = slot.nozzleType?.trim() ?? '';
  final material = switch (nozzleMaterialOf(type)) {
    NozzleMaterial.stainless => l10n.nozzleMaterialStainless,
    NozzleMaterial.hardened => l10n.nozzleMaterialHardened,
    NozzleMaterial.tungsten => l10n.nozzleMaterialTungsten,
    // The code as the printer sent it, as the web does.
    null => type,
  };
  final flow = switch (nozzleHighFlowStated(type)) {
    true => l10n.nozzleFlowHigh,
    false => l10n.nozzleFlowStandard,
    null => '',
  };
  final wear = slot.wear;
  final printTime = slot.printTimeS;
  final maxTemp = slot.maxTemp ?? 0;
  final serial = slot.serialNumber?.trim() ?? '';
  final filament = parseTrayColor(slot.filamentColor);
  final filamentType = slot.filamentType?.trim() ?? '';
  final hasFilament =
      (filament != null && filament.a != 0) || filamentType.isNotEmpty;

  final rows = <FactRow>[
    if (diameter.isNotEmpty)
      FactRow(
        label: l10n.nozzleLabelDiameter,
        value: l10n.nozzleDiameterValue(diameter),
      ),
    if (full && material.isNotEmpty)
      FactRow(label: l10n.nozzleLabelType, value: material),
    if (flow.isNotEmpty) FactRow(label: l10n.nozzleLabelFlow, value: flow),
    if (full && status != null)
      FactRow(label: l10n.nozzleLabelStatus, value: status),
    if (wear != null)
      FactRow(label: l10n.nozzleLabelWear, value: l10n.nozzleWearValue(wear)),
    if (printTime != null && printTime >= 0)
      FactRow(
        label: l10n.nozzleLabelPrintTime,
        value: formatSeconds(l10n, printTime),
      ),
    if (full && maxTemp > 0)
      FactRow(
        label: l10n.nozzleLabelMaxTemp,
        value: l10n.nozzleMaxTempValue(maxTemp),
      ),
    if (full && serial.isNotEmpty)
      FactRow.custom(
        label: l10n.nozzleLabelSerial,
        value: Text(serial, style: t.monoValue.copyWith(color: t.textPrimary)),
      ),
    if (full && hasFilament)
      FactRow.custom(
        label: l10n.nozzleLabelFilament,
        value: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (filament != null && filament.a != 0) _FigureDot(filament),
            // The gap only between a dot and a name, so a colour alone sits
            // against the end of the row like every other value.
            if (filament != null && filament.a != 0 && filamentType.isNotEmpty)
              const SizedBox(width: DashSpace.sm),
            if (filamentType.isNotEmpty) Flexible(child: Text(filamentType)),
          ],
        ),
      ),
  ];
  return rows;
}

/// A filament colour as a round mark, outlined so black and white show on both
/// themes (as `FilamentDot` does for an archive, from a parsed colour here).
class _FigureDot extends StatelessWidget {
  const _FigureDot(this.color);

  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Container(
      width: DashSize.d12,
      height: DashSize.d12,
      decoration: BoxDecoration(
        color: Color.alphaBlend(color, t.overlaySurface),
        shape: BoxShape.circle,
        border: Border.all(color: t.textTertiary),
      ),
    );
  }
}

/// The sheet a rack chip opens: the nozzle's figures under its position.
Future<void> showNozzleSheet(
  BuildContext context, {
  required int position,
  required NozzleRackSlot slot,
  required bool mounted,
}) => dashSurfaceSheet<void>(
  context,
  builder: (sheetContext) {
    final t = DashTokens.of(sheetContext);
    final l10n = AppLocalizations.of(sheetContext);
    return FittedSheetSurface(
      child: Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            DashSpace.gutter,
            DashSpace.lg,
            DashSpace.gutter,
            DashSpace.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.nozzleSheetTitle(position), style: t.titleLg),
              const SizedBox(height: DashSpace.md),
              NozzleFigures(
                slot: slot,
                status: mounted
                    ? l10n.nozzleStatusMounted
                    : l10n.nozzleStatusDocked,
              ),
            ],
          ),
        ),
      ),
    );
  },
);

/// A hotend's figures under their own heading, for the end of its temperature
/// sheet. Nothing at all when the printer reported none for this nozzle.
class _NozzleSection extends StatelessWidget {
  const _NozzleSection(this.slot);

  final NozzleRackSlot slot;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_nozzleRows(
      DashTokens.of(context),
      l10n,
      slot,
      NozzleFigureSet.hotend,
      null,
    ).isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: DashSpace.xl),
        SectionLabel(l10n.nozzleSectionTitle),
        const SizedBox(height: DashSpace.sm),
        NozzleFigures(slot: slot, set: NozzleFigureSet.hotend),
      ],
    );
  }
}
