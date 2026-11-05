import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/printer.dart';
import '../../../core/models/smart_plug.dart';
import '../../../core/theme/dash_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../smart_plugs_providers.dart';

/// Plugs feeding one printer, or — with a null [printer] — the plugs assigned
/// to no printer this session knows.
typedef PowerGroup = ({Printer? printer, List<SmartPlug> plugs});

/// Every plug, disabled ones included: one group per printer in the order of
/// [printers] (the dashboard's sort, its filters left out), then a single
/// group of the unassigned ones. A plug pointing at a printer missing from
/// [printers] counts as unassigned rather than vanishing from the breakdown.
List<PowerGroup> groupPlugsByPrinter(
  List<SmartPlug> plugs,
  List<Printer> printers,
) {
  final byPrinter = <int, List<SmartPlug>>{};
  final unassigned = <SmartPlug>[];
  final known = {for (final p in printers) p.id};
  for (final plug in plugs) {
    final id = plug.printerId;
    if (id != null && known.contains(id)) {
      byPrinter.putIfAbsent(id, () => []).add(plug);
    } else {
      unassigned.add(plug);
    }
  }
  return [
    for (final printer in printers)
      if (byPrinter[printer.id] case final group?)
        (printer: printer, plugs: group..sort(SmartPlug.compareAsMainPlug)),
    if (unassigned.isNotEmpty)
      (
        printer: null,
        plugs: unassigned
          ..sort(
            (a, b) => _plugLabel(
              a,
            ).toLowerCase().compareTo(_plugLabel(b).toLowerCase()),
          ),
      ),
  ];
}

String _plugLabel(SmartPlug plug) => plug.name ?? '#${plug.id}';

/// Sum of the readings among [plugs]; null when none of them has one, so a
/// printer whose plugs are all silent reads "—" rather than "0 W".
double? _powerOf(SmartPlugsState state, Iterable<SmartPlug> plugs) {
  double? sum;
  for (final plug in plugs) {
    final w = state.statusFor(plug.id)?.powerW;
    if (w != null) sum = (sum ?? 0) + w;
  }
  return sum;
}

const _iconSize = 20.0;
const _dotSize = 8.0;
const _heroFontSize = 34.0;
const _heroBoltSize = 28.0;
const _barHeight = 10.0;

Future<void> showPowerBreakdownSheet(
  BuildContext context, {
  required List<Printer> printers,
}) => dashSheet<void>(
  context,
  builder: (_) => PowerBreakdownSheet(printers: printers),
);

class PowerBreakdownSheet extends ConsumerWidget {
  const PowerBreakdownSheet({super.key, required this.printers});

  final List<Printer> printers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(smartPlugsProvider);
    final groups = groupPlugsByPrinter(state.plugs, printers);

    String watts(double? w) => w == null ? '—' : l10n.powerWatts(w.round());

    Widget plugLine(SmartPlug plug, {required bool showWatts}) {
      final on = state.effectiveOn(plug);
      return Padding(
        padding: const EdgeInsets.only(top: DashSpace.xs),
        child: Row(
          children: [
            SizedBox(
              width: _iconSize,
              child: Center(
                child: Semantics(
                  label: switch (on) {
                    true => l10n.plugStateOn,
                    false => l10n.plugStateOff,
                    null => null,
                  },
                  child: Container(
                    width: _dotSize,
                    height: _dotSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: on == true ? t.accentGreen : null,
                      border: on == true
                          ? null
                          : Border.all(
                              color: t.textTertiary,
                              width: DashStroke.regular,
                            ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: DashSpace.sm),
            Expanded(
              child: Text(
                _plugLabel(plug),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.labelSoft.copyWith(color: t.textSecondary),
              ),
            ),
            if (showWatts) ...[
              const SizedBox(width: DashSpace.md),
              Text(
                watts(_powerOf(state, [plug])),
                style: t.monoValue.copyWith(
                  color: t.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ],
        ),
      );
    }

    // One colour per tile, shared with its segment of the bar; past the palette
    // the rest pool in grey, as on the stats ring.
    Color colorOf(int i) =>
        i < seriesPalette.length ? seriesPalette[i] : t.textTertiary;

    Widget tile(PowerGroup g, Color color) => Container(
      margin: const EdgeInsets.only(bottom: DashSpace.sm),
      padding: const EdgeInsets.all(DashSpace.md),
      decoration: BoxDecoration(
        color: t.subCard,
        borderRadius: BorderRadius.circular(DashRadius.lg),
        border: Border.all(color: t.subCardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                g.printer == null ? Icons.power_outlined : Icons.print_outlined,
                size: _iconSize,
                color: color,
              ),
              const SizedBox(width: DashSpace.sm),
              Expanded(
                child: Text(
                  g.printer?.name ?? l10n.powerUnassignedPlugs,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.body.copyWith(color: t.textPrimary),
                ),
              ),
              const SizedBox(width: DashSpace.md),
              Text(
                watts(_powerOf(state, g.plugs)),
                style: t.monoValue.copyWith(
                  color: t.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          // A printer on a single plug needs no watts of its own per plug.
          for (final plug in g.plugs)
            plugLine(plug, showWatts: g.printer == null || g.plugs.length > 1),
        ],
      ),
    );

    return logTag(
      'sheet.power_breakdown',
      Padding(
        padding: const EdgeInsets.fromLTRB(
          DashSpace.gutter,
          0,
          DashSpace.gutter,
          DashSpace.lg,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.bolt,
                    size: _heroBoltSize,
                    color: t.accentGreenInk,
                  ),
                  Text(
                    watts(state.totalPowerW),
                    style: t.monoValue.copyWith(
                      fontSize: _heroFontSize,
                      fontWeight: DashWeight.bold,
                      color: t.textPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              Text(
                l10n.powerBreakdownTitle,
                textAlign: TextAlign.center,
                style: t.labelSoft.copyWith(color: t.textSecondary),
              ),
              const SizedBox(height: DashSpace.md),
              _SegmentBar(
                track: t.subCardBorder,
                segments: [
                  for (var i = 0; i < groups.length; i++)
                    (
                      color: colorOf(i),
                      watts: _powerOf(state, groups[i].plugs),
                    ),
                ],
              ),
              const SizedBox(height: DashSpace.lg),
              for (var i = 0; i < groups.length; i++)
                tile(groups[i], colorOf(i)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The total split into one coloured run per tile, each as long as its share.
/// A tile with no reading or 0 W gets no run; with nothing drawing power at
/// all, only the track shows.
class _SegmentBar extends StatelessWidget {
  const _SegmentBar({required this.track, required this.segments});

  final Color track;
  final List<({Color color, double? watts})> segments;

  @override
  Widget build(BuildContext context) {
    final drawing = [
      for (final s in segments)
        if ((s.watts ?? 0) > 0) s,
    ];
    return ClipRRect(
      borderRadius: BorderRadius.circular(_barHeight / 2),
      child: Container(
        height: _barHeight,
        color: track,
        child: Row(
          // A childless ColoredBox takes the smallest height it is allowed,
          // which under the default centred alignment is zero.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final s in drawing)
              Expanded(
                // Flex is an int: tenths of a watt keep a 0.4 W lamp visible
                // next to a 100 W printer instead of rounding it away.
                flex: (s.watts! * 10).round().clamp(1, 1 << 30),
                child: ColoredBox(color: s.color),
              ),
          ],
        ),
      ),
    );
  }
}
