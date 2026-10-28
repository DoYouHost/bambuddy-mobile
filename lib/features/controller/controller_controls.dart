import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/printer_status.dart';
import '../../core/models/smart_plug.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import '../../providers.dart';
import '../dashboard/controls_providers.dart';
import '../dashboard/smart_plug_actions.dart';
import '../dashboard/smart_plugs_providers.dart';
import '../dashboard/temp_readings.dart';
import '../dashboard/widgets/pill_switch.dart';
import 'scale_to_fit.dart';

// The widgets below fill the height they are given: the Overview divides its
// column between them (`controller_overview.dart`), so each one is built to
// stretch; their size comes from the one scale over the whole body
// (`scale_to_fit.dart`), never from their own room.

/// The sensors worth a tile, in the printer card's order.
List<TempReading> controllerReadings(PrinterStatus status) => [
  for (final r in buildTempReadings(
    status.temperatures,
    status.airductIsHeating,
  ))
    if (r.kind != TempKind.unknown) r,
];

/// Speed is offered while printing only, as the printer card does, and not to a
/// session the server refuses control to.
bool controllerSpeedVisible(PrinterStatus status, {required bool refused}) =>
    (status.connected ?? false) && status.isPrinting && !refused;

/// The light needs a printer that answers and a session that may drive it; the
/// plug is shown whenever the printer has one.
bool controllerLightVisible(PrinterStatus status, {required bool refused}) =>
    (status.connected ?? false) && !refused;

/// Nozzle, bed and chamber as they are now and where they are heading, with the
/// active nozzle outlined on a dual-nozzle printer. Read-only here: setting a
/// target belongs to the Heat tab.
class ControllerReadings extends StatelessWidget {
  const ControllerReadings({super.key, required this.status});

  final PrinterStatus status;

  /// The most readings in a row that still show their target.
  static const _targetBeside = 3;

  @override
  Widget build(BuildContext context) {
    final readings = controllerReadings(status);
    // A second nozzle key is what says the printer has two heads.
    final dual = readings.any(
      (r) => r.kind == TempKind.nozzle && r.index != null,
    );
    // At a large text size the readings are lines of a grid of two, each one
    // line tall: four tall tiles in a row need more width than the box has.
    if (controllerLargeText(context)) {
      Widget tile(TempReading r) => ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: kMinInteractiveDimension + DashSpace.xs,
        ),
        child: _ReadingTile(
          reading: r,
          dual: dual,
          showTarget: false,
          active: dual && _isActive(r, status.activeExtruder),
          compact: true,
        ),
      );
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < readings.length; i += 2) ...[
            if (i > 0) const SizedBox(height: DashSpace.sm),
            Row(
              children: [
                Expanded(child: tile(readings[i])),
                const SizedBox(width: DashSpace.sm),
                Expanded(
                  child: i + 1 < readings.length
                      ? tile(readings[i + 1])
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ],
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, r) in readings.indexed) ...[
          if (i > 0) const SizedBox(width: DashSpace.sm),
          Expanded(
            child: _ReadingTile(
              reading: r,
              dual: dual,
              // Four across leave a tile too narrow for "250° / 250°" at the
              // size of its neighbours; the target is on the Heat tab, and a
              // tile that scaled its own text to fit made each one a
              // different size.
              showTarget: readings.length <= _targetBeside,
              active: dual && _isActive(r, status.activeExtruder),
            ),
          ),
        ],
      ],
    );
  }

  /// The plain `nozzle` key is the left head and `nozzle_2` the right one, and
  /// the server numbers extruders 0 = right, 1 = left — the same mapping the
  /// printer card uses for its nozzle switch.
  static bool _isActive(TempReading r, int? activeExtruder) {
    if (r.kind != TempKind.nozzle) return false;
    final hardwareIndex = r.index != null ? 0 : 1;
    return hardwareIndex == (activeExtruder ?? 0);
  }
}

class _ReadingTile extends ConsumerWidget {
  const _ReadingTile({
    required this.reading,
    required this.dual,
    required this.showTarget,
    required this.active,
    this.compact = false,
  });

  final TempReading reading;
  final bool dual;
  final bool showTarget;
  final bool active;

  /// One line: the dot, the name and the reading, with no bar. The tile for a
  /// large text size, where four tall tiles do not fit a row.
  final bool compact;

  static const _dot = 8.0;
  static const _bar = 4.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final chamberMax = ref.watch(chamberMaxTargetProvider);
    final actual = reading.actual;
    final target = reading.target;
    final color = reading.gaugeColor(t);
    // On two heads the plain key is the first nozzle, not "the" nozzle.
    final label =
        dual && reading.kind == TempKind.nozzle && reading.index == null
        ? l10n.tempNozzleNumbered('1')
        : reading.label(l10n);
    final radius = BorderRadius.circular(DashSpace.md + DashSpace.xs);
    final readingText = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: actual == null ? '—' : '${actual.round()}°',
            style: t.monoHeadline.copyWith(color: reading.gaugeInk(t)),
          ),
          if (showTarget && target != null && target > 0)
            TextSpan(
              text: ' / ${target.round()}°',
              style: t.monoValue.copyWith(color: t.textTertiary),
            ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    return Semantics(
      container: true,
      // The outline says which nozzle is active; a reader is told the same.
      selected: active,
      label: [
        label,
        if (actual != null) '${actual.round()}°',
        if (target != null && target > 0) '/ ${target.round()}°',
      ].join(' '),
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.fromLTRB(
            DashSpace.md,
            DashSpace.sm,
            DashSpace.md,
            DashSpace.sm,
          ),
          decoration: BoxDecoration(
            color: active ? t.accent.withValues(alpha: 0.08) : t.subCard,
            borderRadius: radius,
            border: Border.all(
              color: active
                  ? t.accent.withValues(alpha: 0.45)
                  : t.subCardBorder,
            ),
          ),
          // The label on the top edge, the bar on the bottom one, and the reading
          // centred between them.
          child: compact
              ? Row(
                  children: [
                    Container(
                      width: _dot,
                      height: _dot,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: DashSpace.sm),
                    Expanded(
                      child: Text(
                        label,
                        style: t.body.copyWith(color: t.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    readingText,
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: _dot,
                          height: _dot,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: DashSpace.sm),
                        Expanded(
                          child: Text(
                            label,
                            style: t.body.copyWith(color: t.textSecondary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    Expanded(child: Center(child: readingText)),
                    // The same sweep as the Heat tab's ring, so the two agree.
                    DashProgressBar(
                      value: actual == null
                          ? 0
                          : (actual / reading.gaugeMax(chamberMax)).clamp(
                              0.0,
                              1.0,
                            ),
                      height: _bar,
                      color: color,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// The speed levels the printer has, 1 (silent) to 4 (ludicrous).
const _speedLevels = [1, 2, 3, 4];

String _speedName(AppLocalizations l10n, int level) => switch (level) {
  1 => l10n.speedSilent,
  2 => l10n.speedStandard,
  3 => l10n.speedSport,
  _ => l10n.speedLudicrous,
};

/// The print speed as one select. Built only where [controllerSpeedVisible] says
/// so. A select, not four buttons: it frees the column's height for the rest.
class ControllerSpeed extends ConsumerWidget {
  const ControllerSpeed({
    super.key,
    required this.printerId,
    required this.status,
  });

  final int printerId;
  final PrinterStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final pending = ref.watch(
      controlsProvider.select((s) => s.pendingFor(printerId)),
    );
    final current = pending.speedLevel ?? status.speedLevel;
    final busy = pending.isBusy(ControlAction.speed);
    String entry(int level) =>
        '${_speedName(l10n, level)} · ${PrinterStatus.speedPercentFor(level)}%';
    return dashCombo<int>(
      context,
      id: 'controller.speed',
      // The field keeps the value it was built with, so a speed that changed
      // under it (the printer's own knob, another phone) rebuilds it.
      fieldKey: ValueKey(current),
      label: Text(l10n.ctrlSpeed),
      initialSelection: current,
      enabled: !busy,
      textStyle: t.bodyBold,
      entries: [
        for (final level in _speedLevels)
          DropdownMenuEntry<int>(
            value: level,
            label: entry(level),
            labelWidget: logTag('controller.speed.$level', Text(entry(level))),
          ),
      ],
      onSelected: (level) {
        if (level != null && level != current) _setSpeed(context, ref, level);
      },
    );
  }

  Future<void> _setSpeed(BuildContext context, WidgetRef ref, int mode) async {
    final l10n = AppLocalizations.of(context);
    final result = await ref
        .read(controlsProvider.notifier)
        .setSpeed(printerId, mode);
    if (!context.mounted) return;
    final msg = result.messageFor(l10n);
    if (msg != null) {
      ScaffoldMessenger.of(context).snack(msg, clearQueue: true);
    }
  }
}

/// The chamber light and, when the printer has one, its smart plug. Built only
/// where the Overview found at least one of them to show.
class ControllerSwitches extends ConsumerWidget {
  const ControllerSwitches({
    super.key,
    required this.printerId,
    required this.status,
  });

  final int printerId;
  final PrinterStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final refused = ref.watch(
      controlRefusedProvider(ControlPermission.control),
    );
    final plug = ref.watch(
      smartPlugsProvider.select((s) => s.plugForPrinterCard(printerId)),
    );
    final tiles = [
      if (controllerLightVisible(status, refused: refused))
        _light(context, ref),
      if (plug != null) _plug(context, ref, plug),
    ];
    // At a large text size each switch is a line of its own, the height of a
    // finger: two side by side no longer fit their names.
    if (controllerLargeText(context)) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, tile) in tiles.indexed) ...[
            if (i > 0) const SizedBox(height: DashSpace.sm),
            SizedBox(height: kMinInteractiveDimension, child: tile),
          ],
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, tile) in tiles.indexed) ...[
          if (i > 0) const SizedBox(width: DashSpace.sm),
          Expanded(child: tile),
        ],
      ],
    );
  }

  Widget _light(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final pending = ref.watch(
      controlsProvider.select((s) => s.pendingFor(printerId)),
    );
    final on = pending.light ?? status.chamberLight ?? false;
    final busy = pending.isBusy(ControlAction.light);
    return _SwitchTile(
      id: 'controller.light',
      icon: on ? Icons.lightbulb : Icons.lightbulb_outline,
      label: l10n.ctrlLight,
      on: on,
      busy: busy,
      onTap: busy ? null : () => _setLight(context, ref, !on),
    );
  }

  Future<void> _setLight(BuildContext context, WidgetRef ref, bool on) async {
    final l10n = AppLocalizations.of(context);
    final result = await ref
        .read(controlsProvider.notifier)
        .setLight(printerId, on: on);
    if (!context.mounted) return;
    final msg = result.messageFor(l10n);
    if (msg != null) {
      ScaffoldMessenger.of(context).snack(msg, clearQueue: true);
    }
  }

  /// The printer card's plug rules: not while printing, not for a monitor-only
  /// plug, not when the plug does not answer or the session may not, and every
  /// change asks first. A tile that cannot be used shows a lock, and its tooltip
  /// says which of those it is.
  Widget _plug(BuildContext context, WidgetRef ref, SmartPlug plug) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(smartPlugsProvider);
    final plugStatus = state.statusFor(plug.id);
    final on = state.effectiveOn(plug) ?? false;
    final busy = state.isBusy(plug.id);
    final reachable = plugStatus?.isReachable ?? true;
    final power = plugStatus?.powerW;
    final printing = status.isPrinting;
    final canControl =
        !plug.isMonitorOnly &&
        !busy &&
        !state.forbidden &&
        reachable &&
        !printing;
    final reason = printing
        ? l10n.smartPlugCantPowerOff
        : plug.isMonitorOnly
        ? l10n.smartPlugMonitorOnly
        : !reachable
        ? l10n.smartPlugUnreachable
        : state.forbidden
        ? l10n.ctrlForbidden
        : null;
    return _SwitchTile(
      id: 'controller.smart_plug',
      icon: on ? Icons.power : Icons.power_off,
      label: l10n.controllerPower,
      sub: on && power != null
          ? l10n.powerWatts(power.round())
          : (on ? l10n.smartPlugOn : l10n.smartPlugOff),
      on: on,
      busy: busy,
      lockedReason: busy ? null : reason,
      onTap: canControl
          ? () => confirmAndSwitchPlug(
              context,
              ref,
              plug,
              !on,
              confirmId: 'controller.smart_plug_confirm',
            )
          : null,
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.id,
    required this.icon,
    required this.label,
    required this.on,
    required this.busy,
    required this.onTap,
    this.sub,
    this.lockedReason,
  });

  final String id;
  final IconData icon;
  final String label;
  final String? sub;
  final bool on;
  final bool busy;

  /// Non-null locks the tile: a lock replaces the switch and the tooltip says
  /// why, so the lock is never unexplained.
  final String? lockedReason;

  /// Null leaves the tile unreachable, which is what the lock or a busy command
  /// looks like.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final large = controllerLargeText(context);
    final radius = BorderRadius.circular(DashSpace.md + DashSpace.xs);
    final tile = Material(
      color: on ? t.accent.withValues(alpha: 0.10) : t.subCard,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(
          color: on ? t.accent.withValues(alpha: 0.35) : t.subCardBorder,
        ),
      ),
      child: logTag(
        id,
        InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: DashSpace.md),
            child: Row(
              children: [
                Icon(icon, color: on ? t.accentInk : t.textSecondary),
                const SizedBox(width: DashSpace.md),
                Expanded(
                  child: Center(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            // One line at a large text size, where a second
                            // line does not fit the height of a finger.
                            large && sub != null ? '$label · $sub' : label,
                            style: t.bodyBold.copyWith(color: t.textPrimary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (sub != null && !large)
                            Text(sub!, style: t.monoLabel),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: DashSpace.sm),
                if (busy)
                  const DashSpinner(size: DashSpace.xl)
                else if (lockedReason != null)
                  Icon(Icons.lock_outline, color: t.textTertiary)
                else
                  PillSwitch(on: on, tokens: t),
              ],
            ),
          ),
        ),
        selected: on,
      ),
    );
    final reason = lockedReason;
    return reason == null ? tile : Tooltip(message: reason, child: tile);
  }
}

/// Said once at the top of a tab when the server refuses this session control:
/// every stepper, slider and jog on it is dead, and a dead control must say why.
class ControllerForbidden extends StatelessWidget {
  const ControllerForbidden({super.key});

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Row(
      children: [
        Icon(
          Icons.lock_outline,
          size: controllerIconSize(context, DashSpace.lg),
          color: t.textSecondary,
        ),
        const SizedBox(width: DashSpace.sm),
        Expanded(
          child: Text(
            AppLocalizations.of(context).ctrlForbidden,
            style: t.labelSoft.copyWith(color: t.textSecondary),
          ),
        ),
      ],
    );
  }
}

/// Height of the tabs' presets, −/+ steps and actions, so buttons that do the
/// same kind of thing are the same size wherever they sit. The Move tab's jogs
/// are the exception: they have no height of their own and fill their cell.
const controllerButtonHeight = 56.0;

/// Every button of the controller that is not a call to action: a filled tile
/// with a border. Never a bare outline, which all but
/// vanishes on the dark ground — disabled, where most jogs sit while a print
/// runs, most of all.
///
/// [tone] paints an enabled tile, its border and its icon in a colour, so what a
/// button moves can be read before the label; [ink] is the icon and text colour
/// where the tone itself would be too pale on a light theme. A disabled button
/// is grey whatever its tone, so a colour means "this one works".
ButtonStyle controllerButtonStyle(
  DashTokens t, {
  Size? minimumSize,
  EdgeInsetsGeometry? padding,
  BorderSide? side,
  Color? tone,
  Color? ink,
}) {
  final base = tone ?? t.textPrimary;
  // Pulled toward the text colour: the bare accent is too pale on a light tile.
  final text =
      ink ?? (tone == null ? null : Color.lerp(tone, t.textPrimary, 0.3));
  final grey = BorderSide(color: t.textPrimary.withValues(alpha: 0.22));
  final enabledSide =
      side ??
      BorderSide(color: base.withValues(alpha: tone == null ? 0.22 : 0.5));
  return FilledButton.styleFrom(
    // A wash of the text colour: `subCard` is a 2% tint and `subCardBorder` a
    // 5% one, which is a border with nothing inside it on this ground.
    backgroundColor: base.withValues(alpha: tone == null ? 0.16 : 0.22),
    foregroundColor: text ?? t.textPrimary,
    disabledBackgroundColor: t.textPrimary.withValues(alpha: 0.11),
    disabledForegroundColor: t.textSecondary,
    minimumSize: minimumSize,
    padding: padding,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(DashSpace.md),
    ),
  ).copyWith(
    side: WidgetStateProperty.resolveWith(
      (states) =>
          states.contains(WidgetState.disabled) ? side ?? grey : enabledSide,
    ),
  );
}

/// A row of choices, one of them picked: the Move tab's step and length, the
/// saver's idle time. Every choice is a button of [controllerButtonHeight];
/// [id] tags each of them, and the row reports the index picked.
class ControllerChoices extends StatelessWidget {
  const ControllerChoices({
    super.key,
    required this.id,
    required this.labels,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
    this.selectLabel,
  });

  final String id;
  final List<String> labels;
  final int selected;
  final bool enabled;
  final ValueChanged<int> onChanged;

  /// Set where the row is a list of presets: at a large text size they no longer
  /// fit side by side, so the row becomes a select with this as its label. A row
  /// of two short views (null) stays a row at any size.
  final String? selectLabel;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final radius = BorderRadius.circular(DashSpace.md);
    if (selectLabel != null && controllerLargeText(context)) {
      return dashCombo<int>(
        context,
        id: id,
        // The field keeps the value it was built with.
        fieldKey: ValueKey(selected),
        label: Text(selectLabel!),
        initialSelection: selected < 0 ? null : selected,
        enabled: enabled,
        textStyle: t.monoValue,
        entries: [
          for (final (i, label) in labels.indexed)
            DropdownMenuEntry<int>(
              value: i,
              label: label,
              labelWidget: logTag('$id.option', Text(label)),
            ),
        ],
        onSelected: (i) {
          if (i != null) onChanged(i);
        },
      );
    }
    return Row(
      children: [
        for (final (i, label) in labels.indexed) ...[
          if (i > 0) const SizedBox(width: DashSpace.sm),
          Expanded(
            child: logTag(
              id,
              Material(
                color: i == selected
                    ? t.accent.withValues(alpha: 0.16)
                    : t.subCard,
                shape: RoundedRectangleBorder(
                  borderRadius: radius,
                  side: BorderSide(
                    color: i == selected
                        ? t.accent.withValues(alpha: 0.4)
                        : t.subCardBorder,
                  ),
                ),
                child: InkWell(
                  borderRadius: radius,
                  onTap: enabled ? () => onChanged(i) : null,
                  child: Container(
                    height: controllerButtonHeight,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(
                      horizontal: DashSpace.xs,
                    ),
                    // One size for every choice: a label that does not fit is
                    // cut, never shrunk on its own. None does in any language.
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: i == selected
                          ? t.monoValue.copyWith(color: t.accentInk)
                          : t.monoValue,
                    ),
                  ),
                ),
              ),
              selected: i == selected,
            ),
          ),
        ],
      ],
    );
  }
}

/// A card of the Heat and Move tabs: one or more [ControllerSection]s side by
/// side, each with its title at the top of the card, and an optional [footer]
/// across the whole width under them for what they share.
class ControllerCard extends StatelessWidget {
  const ControllerCard({super.key, required this.sections, this.footer});

  /// With [shrink] the card is as tall as its content instead of filling the
  /// height it is given: for a card in a page that scrolls.
  ControllerCard.single({
    Key? key,
    required String title,
    Widget? trailing,
    required Widget child,
    bool shrink = false,
  }) : this(
         key: key,
         sections: [
           ControllerSection(
             title: title,
             trailing: trailing,
             shrink: shrink,
             child: child,
           ),
         ],
       );

  final List<ControllerSection> sections;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    // A row that stretches needs a height to stretch to.
    if (sections.length == 1 && this.footer == null && sections.single.shrink) {
      return Container(
        padding: const EdgeInsets.all(DashSpace.md),
        decoration: t.cardBox,
        child: sections.single,
      );
    }
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, s) in sections.indexed) ...[
          if (i > 0) const SizedBox(width: DashSpace.xl),
          Expanded(flex: s.flex, child: s),
        ],
      ],
    );
    final footer = this.footer;
    return Container(
      padding: const EdgeInsets.all(DashSpace.md),
      decoration: t.cardBox,
      child: footer == null
          ? row
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: row),
                const SizedBox(height: DashSpace.md),
                footer,
              ],
            ),
    );
  }
}

/// A title, an optional control beside it, and the content filling the rest.
/// The header is as tall as a touch target whether or not it holds one, so the
/// titles of a row of cards line up.
class ControllerSection extends StatelessWidget {
  const ControllerSection({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.flex = 1,
    this.shrink = false,
  });

  static const headerHeight = 44.0;

  /// The content takes its own height; see [ControllerCard.single].
  final bool shrink;

  final String title;
  final Widget? trailing;
  final Widget child;

  /// Share of the card's width when it holds several sections.
  final int flex;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: shrink ? MainAxisSize.min : MainAxisSize.max,
      children: [
        // A minimum: a trailing button that is taller than the header makes it so.
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: headerHeight),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: t.titleLg,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ?trailing,
            ],
          ),
        ),
        const SizedBox(height: DashSpace.sm),
        if (shrink) child else Expanded(child: child),
      ],
    );
  }
}
