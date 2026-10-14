import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter/material.dart';

import '../../core/models/calibration_option.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';

// Form pieces the queue's edit screen and its bulk edit share: the titled
// section card with its tone stripe, the segmented toggle, and the two option
// rows.

/// How a [QueueSectionCard] folds: [id] is the header's diagnostic id.
typedef QueueSectionCollapse = ({String id, bool open, VoidCallback onToggle});

/// A section's edge stripe, so a section is found by where it was last seen.
/// Filament shares one tone between its two forms, which are never on screen
/// together. The colours are the theme's own series, one per member.
enum QueueSectionTone {
  target,
  plate,
  copies,
  filament,
  options,
  preheat,
  cost,
  schedule;

  Color of(DashTokens t) => t.accentSeries(values.length)[index];
}

/// The stripe down a section's left edge: [_toneSolid] of the colour, then
/// [_toneFade] fading out to the card.
const _toneSolid = 1.0;
const _toneFade = 3.0;

/// Corner radius of a [QueueSectionCard]; the stripe follows it round the corners.
const _sectionRadius = 18.0;

/// Titled card wrapper matching the app's grouped-section look. With [collapse]
/// the title is a button that shows or hides [child].
class QueueSectionCard extends StatelessWidget {
  const QueueSectionCard({
    super.key,
    required this.tone,
    this.title,
    required this.child,
    this.collapse,
  });

  final QueueSectionTone tone;

  /// Absent for a card that is one row and needs no heading.
  final String? title;
  final Widget child;
  final QueueSectionCollapse? collapse;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final fold = collapse;
    final heading = title == null
        ? null
        : Text(title!, style: t.bodyBold.copyWith(letterSpacing: 0.2));
    final open = fold?.open ?? true;
    // The gap under the title belongs to an open card only.
    EdgeInsets headerPadding({required bool open}) => EdgeInsets.fromLTRB(
      DashSpace.lg,
      DashSpace.lg,
      DashSpace.lg,
      open ? DashSpace.md : DashSpace.lg,
    );
    return Container(
      decoration: BoxDecoration(
        color: t.subCard,
        borderRadius: BorderRadius.circular(_sectionRadius),
        border: Border.all(color: t.subCardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                // The colour is the key, so a test can read what a card wears.
                key: ValueKey(tone.of(t)),
                painter: _ToneEdgePainter(tone.of(t)),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (heading != null && fold == null)
                Padding(padding: headerPadding(open: true), child: heading)
              else if (heading != null && fold != null)
                InkWell(
                  onTap: fold.onToggle,
                  child: Padding(
                    padding: headerPadding(open: open),
                    child: Row(
                      children: [
                        Expanded(child: heading),
                        Icon(
                          open ? Icons.expand_less : Icons.expand_more,
                          color: t.textTertiary,
                        ),
                      ],
                    ),
                  ),
                ).tagged(fold.id, expanded: open),
              if (open)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    DashSpace.lg,
                    heading == null ? DashSpace.lg : 0,
                    DashSpace.lg,
                    DashSpace.lg,
                  ),
                  child: child,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A section's colour along the left edge of its card: [_toneSolid] of full
/// colour that fades over the next [_toneFade] towards the inside. Round each of
/// the two left corners the stripe follows the card's arc and narrows to nothing
/// — 4, 3, 2, 1 dp — so it is gone where the arc meets the top or bottom side.
///
/// A mesh with a colour on each vertex: three rows across the stripe (solid,
/// end of solid, transparent) at every step along the edge, the rows squeezing
/// together on the arcs. A stroke cannot narrow, and a gradient painted across
/// the edge cannot bend with a corner.
class _ToneEdgePainter extends CustomPainter {
  const _ToneEdgePainter(this.color);

  final Color color;

  /// The card's border is 1 dp and the painted area sits inside it.
  static const _border = 1.0;

  /// Steps round one corner.
  static const _arcSteps = 24;

  @override
  void paint(Canvas canvas, Size size) {
    const radius = _sectionRadius - _border;
    const width = _toneSolid + _toneFade;
    final rows = [color, color, color.withValues(alpha: 0)];
    // Along the edge from the top end of the top arc to the bottom end of the
    // bottom arc; `reach` is how far round the arc a station is, 0 on the
    // straight part and 1 at the point it meets a side.
    final stations = <({Offset at, Offset inward, double reach})>[];
    void arc(Offset centre, double from, double to, {required bool top}) {
      for (var i = 0; i <= _arcSteps; i++) {
        final along = i / _arcSteps;
        final angle = from + (to - from) * along;
        final out = Offset(math.cos(angle), math.sin(angle));
        stations.add((
          at: centre + out * radius,
          inward: -out,
          reach: top ? 1 - along : along,
        ));
      }
    }

    arc(const Offset(radius, radius), 3 * math.pi / 2, math.pi, top: true);
    arc(Offset(radius, size.height - radius), math.pi, math.pi / 2, top: false);

    // Three points across each station: the edge, where the solid part ends,
    // and where the fade ends — closer together the nearer the end of the arc.
    final positions = <Offset>[];
    final colors = <Color>[];
    for (final st in stations) {
      final w = width * (1 - st.reach);
      for (final (i, depth) in [0.0, w * _toneSolid / width, w].indexed) {
        positions.add(st.at + st.inward * depth);
        colors.add(rows[i]);
      }
    }
    final triangles = <int>[];
    for (var k = 0; k < stations.length - 1; k++) {
      for (var row = 0; row < 2; row++) {
        final a = k * 3 + row;
        final b = (k + 1) * 3 + row;
        triangles.addAll([a, a + 1, b, a + 1, b + 1, b]);
      }
    }
    canvas.drawVertices(
      ui.Vertices(
        ui.VertexMode.triangles,
        positions,
        colors: colors,
        indices: triangles,
      ),
      BlendMode.src,
      Paint(),
    );
  }

  @override
  bool shouldRepaint(_ToneEdgePainter old) => old.color != color;
}

/// A segment for [QueueSegToggle].
typedef QueueSegment<T> = ({T value, String label, IconData? icon});

/// Horizontal pill toggle (Specific/Any, Inherit/On/Off, ASAP/Queue/Schedule).
/// Selected segment is green-filled; the rest are neutral.
class QueueSegToggle<T> extends StatelessWidget {
  const QueueSegToggle({
    super.key,
    required this.id,
    required this.selected,
    required this.segments,
    required this.onChanged,
  });

  /// Log identifier, required from the call site — see [_CheckRow.id]. Six of
  /// these are rendered on this screen and they set six different things, so a
  /// tag written into `build` made a report say only that "a segment in the
  /// queue form" was pressed.
  final String id;

  final T selected;
  final List<QueueSegment<T>> segments;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Row(
      children: [
        for (var i = 0; i < segments.length; i++) ...[
          if (i > 0) const SizedBox(width: DashSpace.sm),
          Expanded(child: _segButton(t, segments[i])),
        ],
      ],
    );
  }

  Widget _segButton(DashTokens t, QueueSegment<T> seg) {
    final isSel = seg.value == selected;
    return Material(
      color: isSel ? t.accentGreen : t.groupCard,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onChanged(seg.value),
        child: Container(
          height: 44,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: DashSpace.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSel ? Colors.transparent : t.groupCardBorder,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (seg.icon != null) ...[
                Icon(
                  seg.icon,
                  size: 16,
                  color: isSel ? t.onAccent : t.textSecondary,
                ),
                const SizedBox(width: DashSpace.sm),
              ],
              Flexible(
                child: Text(
                  seg.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodyBold.copyWith(
                    color: isSel ? t.onAccent : t.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        // The fill is the only thing that says which segment is on.
      ).tagged(id, selected: isSel),
    );
  }
}

/// Title + subtitle row with a trailing [Switch] (print options).
/// One tri-state calibration option.
///
/// bambuddy 1.2.5+ stores `off` / `on` / `auto`, so the row is a three-way
/// segment. Older servers only have the boolean, and they are the reason this
/// falls back to [QueueOptionSwitch] rather than greying a third position out: a
/// position the server cannot store has no honest disabled state, it simply does
/// not exist there.
///
/// The fallback maps `auto` onto the switch's ON side ([CalibrationOption.asSwitch]).
/// That reads right — `auto` still lets the printer calibrate — and it cannot
/// quietly rewrite the stored value, because the save path omits an untouched
/// field entirely (see `_calibrationUpdate`).
class QueueCalibrationRow extends StatelessWidget {
  const QueueCalibrationRow({
    super.key,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.triState,
    required this.onChanged,
  });

  /// One id for both shapes this row takes: the three-way segment and the
  /// two-state switch an older server falls back to are the same setting, and a
  /// log that split them would be naming the server's version rather than the
  /// control the user touched.
  final String id;

  final String title;
  final String subtitle;
  final CalibrationOption value;
  final bool triState;
  final ValueChanged<CalibrationOption> onChanged;

  @override
  Widget build(BuildContext context) {
    if (!triState) {
      return QueueOptionSwitch(
        id: id,
        title: title,
        subtitle: subtitle,
        value: value.asSwitch,
        onChanged: (v) =>
            onChanged(v ? CalibrationOption.on : CalibrationOption.off),
      );
    }
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DashSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: t.titleSm),
          const SizedBox(height: DashSpace.xs),
          Text(subtitle, style: t.labelSoft),
          const SizedBox(height: DashSpace.sm),
          QueueSegToggle<CalibrationOption>(
            id: id,
            selected: value,
            segments: [
              (
                value: CalibrationOption.auto,
                label: l10n.commonAuto,
                icon: null,
              ),
              (value: CalibrationOption.on, label: l10n.commonOn, icon: null),
              (value: CalibrationOption.off, label: l10n.commonOff, icon: null),
            ],
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class QueueOptionSwitch extends StatelessWidget {
  const QueueOptionSwitch({
    super.key,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  /// Log identifier, required from the call site — see [_CheckRow.id].
  final String id;

  final String title;
  final String subtitle;
  final bool value;

  /// Null disables the switch.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DashSpace.sm),
      // Merged, so the switch is announced with the setting it belongs to. On
      // its own it read as "off, switch" — six of these sit on this screen and
      // nothing said which one had focus. The probe treats a merged subtree as
      // one control and keeps the identifier, so the log is unchanged.
      child: MergeSemantics(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: t.titleSm),
                  const SizedBox(height: DashSpace.xs),
                  Text(subtitle, style: t.labelSoft),
                ],
              ),
            ),
            const SizedBox(width: DashSpace.md),
            Switch(
              value: value,
              activeThumbColor: Colors.white,
              activeTrackColor: t.accentGreen,
              onChanged: onChanged,
            ).tagged(id),
          ],
        ),
      ),
    );
  }
}

/// The one action of a queue form, so it carries the app's primary-button fill
/// instead of reading as a third piece of bar text next to the title and the
/// back arrow. Compact padding and a shorter radius keep the pill inside the
/// bar; the rest (colours, disabled state, weight) comes from
/// [dashPrimaryButtonStyle] so it matches every other confirming button. A null
/// [onPressed] disables it.
class QueueSubmitAction extends StatelessWidget {
  const QueueSubmitAction({
    super.key,
    required this.id,
    required this.label,
    required this.onPressed,
  });

  /// Log identifier of the button.
  final String id;

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Padding(
      // Vertical inset leaves the pill room to grow with the text scale before
      // it meets the 56-high bar.
      padding: const EdgeInsets.fromLTRB(
        DashSpace.xs,
        DashSpace.xs,
        DashSpace.md,
        DashSpace.xs,
      ),
      child: FilledButton(
        style: dashPrimaryButtonStyle(t).copyWith(
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: DashSpace.lg),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: onPressed,
        child: Text(label),
      ).tagged(id),
    );
  }
}
