import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter/material.dart';
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

  @override
  Widget build(BuildContext context) {
    final readings = controllerReadings(status);
    // A second nozzle key is what says the printer has two heads.
    final dual = readings.any(
      (r) => r.kind == TempKind.nozzle && r.index != null,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, r) in readings.indexed) ...[
          if (i > 0) const SizedBox(width: DashSpace.sm),
          Expanded(
            child: _ReadingTile(
              reading: r,
              dual: dual,
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
    required this.active,
  });

  final TempReading reading;
  final bool dual;
  final bool active;

  static const _dot = 8.0;
  static const _bar = 4.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final chamberMax = ref.watch(chamberMaxTargetProvider);
    final actual = reading.actual;
    final target = reading.target;
    final state = reading.heatState();
    final color = reading.gaugeColor(t);
    // On two heads the plain key is the first nozzle, not "the" nozzle.
    final label =
        dual && reading.kind == TempKind.nozzle && reading.index == null
        ? l10n.tempNozzleNumbered('1')
        : reading.label(l10n);
    final radius = BorderRadius.circular(DashSpace.md + DashSpace.xs);
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
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
                                Text(
                                  label,
                                  style: t.body.copyWith(
                                    color: t.textSecondary,
                                  ),
                                  maxLines: 1,
                                ),
                              ],
                            ),
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: actual == null
                                        ? '—'
                                        : '${actual.round()}°',
                                    style: t.monoHeadline.copyWith(
                                      color: color,
                                    ),
                                  ),
                                  if (target != null && target > 0)
                                    TextSpan(
                                      text: ' / ${target.round()}°',
                                      style: t.monoValue.copyWith(
                                        color: t.textTertiary,
                                      ),
                                    ),
                                ],
                              ),
                              maxLines: 1,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (state != HeatState.off) ...[
                      const SizedBox(width: DashSpace.xs),
                      // Four heaters on two nozzles leave a narrow tile.
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: ControllerHeatPill(state: state, dense: true),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: DashSpace.xs),
              // The same sweep as the Heat tab's ring, so the two agree.
              DashProgressBar(
                value: actual == null
                    ? 0
                    : (actual / reading.gaugeMax(chamberMax)).clamp(0.0, 1.0),
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

/// Where a heater stands against its target, beside its reading on the Heat
/// tab and on the Overview's tiles.
class ControllerHeatPill extends StatelessWidget {
  const ControllerHeatPill({
    super.key,
    required this.state,
    this.dense = false,
  });

  final HeatState state;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final (label, accent, ink) = switch (state) {
      HeatState.heating => (
        l10n.controllerHeating,
        t.accentOrange,
        t.accentOrangeInk,
      ),
      HeatState.atTarget => (l10n.controllerAtTarget, t.accent, t.accentInk),
      HeatState.cooling ||
      HeatState.off => (l10n.controllerCooling, t.accentBlue, t.accentBlue),
    };
    return DashPill(label: label, accent: accent, accentInk: ink, dense: dense);
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

/// The four print speeds as one row. Built only where [controllerSpeedVisible]
/// says so.
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
    final radius = BorderRadius.circular(DashSpace.md);
    return Container(
      padding: const EdgeInsets.all(DashSpace.xs),
      decoration: BoxDecoration(
        color: t.subCard,
        borderRadius: BorderRadius.circular(DashSpace.md + DashSpace.xs),
        border: Border.all(color: t.subCardBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final level in _speedLevels)
            Expanded(
              child: logTag(
                'controller.speed.$level',
                Material(
                  color: current == level
                      ? t.accent.withValues(alpha: 0.16)
                      : Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: radius,
                    side: current == level
                        ? BorderSide(color: t.accent.withValues(alpha: 0.4))
                        : BorderSide.none,
                  ),
                  child: InkWell(
                    borderRadius: radius,
                    onTap: busy ? null : () => _setSpeed(context, ref, level),
                    child: Center(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _speedName(l10n, level),
                              style: current == level
                                  ? t.bodyBold.copyWith(color: t.accentInk)
                                  : t.bodyBold,
                              maxLines: 1,
                            ),
                            Text(
                              '${PrinterStatus.speedPercentFor(level)}%',
                              style: t.monoLabel,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                selected: current == level,
              ),
            ),
        ],
      ),
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
                            label,
                            style: t.bodyBold.copyWith(color: t.textPrimary),
                            maxLines: 1,
                          ),
                          if (sub != null) Text(sub!, style: t.monoLabel),
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
        Icon(Icons.lock_outline, size: DashSpace.lg, color: t.textSecondary),
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
/// are the exception: they share one height of their own, sized to fill the
/// axes card (`_jogHeight` in `controller_move.dart`).
const controllerButtonHeight = 56.0;

/// A card of the Heat and Move tabs: one or more [ControllerSection]s side by
/// side, each with its title at the top of the card, and an optional [footer]
/// across the whole width under them for what they share.
class ControllerCard extends StatelessWidget {
  const ControllerCard({super.key, required this.sections, this.footer});

  ControllerCard.single({
    Key? key,
    required String title,
    Widget? trailing,
    required Widget child,
  }) : this(
         key: key,
         sections: [
           ControllerSection(title: title, trailing: trailing, child: child),
         ],
       );

  final List<ControllerSection> sections;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
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
  });

  static const headerHeight = 44.0;

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
      children: [
        SizedBox(
          height: headerHeight,
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
        Expanded(child: child),
      ],
    );
  }
}
