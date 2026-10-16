import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/printer_status.dart';
import '../../core/models/smart_plug.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import '../dashboard/controls_providers.dart';
import '../dashboard/smart_plug_actions.dart';
import '../dashboard/smart_plugs_providers.dart';
import '../dashboard/temp_readings.dart';
import '../dashboard/widgets/pill_switch.dart';

/// Nozzle, bed and chamber as they are now and where they are heading, with the
/// active nozzle outlined on a dual-nozzle printer. Read-only here: setting a
/// target belongs to the Heat tab.
class ControllerReadings extends StatelessWidget {
  const ControllerReadings({super.key, required this.status});

  final PrinterStatus status;

  @override
  Widget build(BuildContext context) {
    final readings = [
      for (final r in buildTempReadings(
        status.temperatures,
        status.airductIsHeating,
      ))
        if (r.kind != TempKind.unknown) r,
    ];
    if (readings.isEmpty) return const SizedBox.shrink();
    // A second nozzle key is what says the printer has two heads.
    final dual = readings.any(
      (r) => r.kind == TempKind.nozzle && r.index != null,
    );
    return Padding(
      padding: const EdgeInsets.only(top: DashSpace.md),
      child: Row(
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
      ),
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

class _ReadingTile extends StatelessWidget {
  const _ReadingTile({
    required this.reading,
    required this.dual,
    required this.active,
  });

  final TempReading reading;
  final bool dual;
  final bool active;

  static const _minHeight = 64.0;
  static const _dot = 8.0;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final actual = reading.actual;
    final target = reading.target;
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
          constraints: const BoxConstraints(minHeight: _minHeight),
          padding: const EdgeInsets.symmetric(
            horizontal: DashSpace.md,
            vertical: DashSpace.sm,
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
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: _dot,
                    height: _dot,
                    decoration: BoxDecoration(
                      color: reading.gaugeColor(t),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: DashSpace.sm),
                  Flexible(
                    child: Text(
                      label,
                      style: t.labelSoft.copyWith(color: t.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: actual == null ? '—' : '${actual.round()}°',
                      style: t.monoValue,
                    ),
                    if (target != null && target > 0)
                      TextSpan(text: '/${target.round()}°', style: t.monoLabel),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The printer's own speed scale and the percentage each level stands for.
const _speedLevels = {1: 50, 2: 100, 3: 124, 4: 166};

String _speedName(AppLocalizations l10n, int level) => switch (level) {
  1 => l10n.speedSilent,
  2 => l10n.speedStandard,
  3 => l10n.speedSport,
  _ => l10n.speedLudicrous,
};

/// The four print speeds as one row. Offered while printing only, as the printer
/// card does; hidden for a session the server refuses control to.
class ControllerSpeed extends ConsumerWidget {
  const ControllerSpeed({
    super.key,
    required this.printerId,
    required this.status,
  });

  final int printerId;
  final PrinterStatus status;

  static const _minHeight = 44.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!(status.connected ?? false) || !status.isPrinting) {
      return const SizedBox.shrink();
    }
    if (ref.watch(controlRefusedProvider(ControlPermission.control))) {
      return const SizedBox.shrink();
    }
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final pending = ref.watch(
      controlsProvider.select((s) => s.pendingFor(printerId)),
    );
    final level = pending.speedLevel ?? status.speedLevel;
    final busy = pending.isBusy(ControlAction.speed);
    final radius = BorderRadius.circular(DashSpace.md);
    return Padding(
      padding: const EdgeInsets.only(top: DashSpace.md),
      child: Container(
        padding: const EdgeInsets.all(DashSpace.xs),
        decoration: BoxDecoration(
          color: t.subCard,
          borderRadius: BorderRadius.circular(DashSpace.md + DashSpace.xs),
          border: Border.all(color: t.subCardBorder),
        ),
        child: Row(
          children: [
            for (final entry in _speedLevels.entries)
              Expanded(
                child: logTag(
                  'controller.speed.${entry.key}',
                  Material(
                    color: level == entry.key
                        ? t.accent.withValues(alpha: 0.16)
                        : Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: radius,
                      side: level == entry.key
                          ? BorderSide(color: t.accent.withValues(alpha: 0.4))
                          : BorderSide.none,
                    ),
                    child: InkWell(
                      borderRadius: radius,
                      onTap: busy
                          ? null
                          : () => _setSpeed(context, ref, entry.key),
                      child: Container(
                        constraints: const BoxConstraints(
                          minHeight: _minHeight,
                        ),
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _speedName(l10n, entry.key),
                              style: level == entry.key
                                  ? t.bodyBold.copyWith(color: t.accentInk)
                                  : t.bodyBold,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text('${entry.value}%', style: t.monoLabel),
                          ],
                        ),
                      ),
                    ),
                  ),
                  selected: level == entry.key,
                ),
              ),
          ],
        ),
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

/// The chamber light and, when the printer has one, its smart plug.
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
    final connected = status.connected ?? false;
    final forbidden = ref.watch(
      controlRefusedProvider(ControlPermission.control),
    );
    final plug = ref.watch(
      smartPlugsProvider.select((s) => s.plugForPrinterCard(printerId)),
    );
    final tiles = [
      if (connected && !forbidden) _light(context, ref),
      if (plug != null) _plug(context, ref, plug),
    ];
    if (tiles.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: DashSpace.md),
      child: Row(
        children: [
          for (final (i, tile) in tiles.indexed) ...[
            if (i > 0) const SizedBox(width: DashSpace.sm),
            Expanded(child: tile),
          ],
        ],
      ),
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

  /// Same rules as the printer card's plug button: not while printing (the
  /// reason is the tile's tooltip), not for a monitor-only plug, not when the
  /// plug does not answer, and every change asks first.
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
    return _SwitchTile(
      id: 'controller.smart_plug',
      icon: on ? Icons.power : Icons.power_off,
      label: l10n.controllerPower,
      sub: on && power != null
          ? l10n.powerWatts(power.round())
          : (on ? l10n.smartPlugOn : l10n.smartPlugOff),
      on: on,
      busy: busy,
      locked: !canControl && !busy && (printing || plug.isMonitorOnly),
      lockedReason: printing
          ? l10n.smartPlugCantPowerOff
          : l10n.smartPlugMonitorOnly,
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
    this.locked = false,
    this.lockedReason,
  });

  final String id;
  final IconData icon;
  final String label;
  final String? sub;
  final bool on;
  final bool busy;
  final bool locked;

  /// Said by the tooltip of a locked tile, so the lock is never unexplained.
  final String? lockedReason;

  /// Null leaves the tile unreachable, which is what the lock or a busy command
  /// looks like.
  final VoidCallback? onTap;

  static const _minHeight = 56.0;

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
          child: Container(
            constraints: const BoxConstraints(minHeight: _minHeight),
            padding: const EdgeInsets.symmetric(horizontal: DashSpace.md),
            child: Row(
              children: [
                Icon(icon, color: on ? t.accentInk : t.textSecondary),
                const SizedBox(width: DashSpace.md),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: t.bodyBold.copyWith(color: t.textPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (sub != null) Text(sub!, style: t.monoLabel),
                    ],
                  ),
                ),
                const SizedBox(width: DashSpace.sm),
                if (busy)
                  const DashSpinner(size: DashSpace.xl)
                else if (locked)
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
    return locked && lockedReason != null
        ? Tooltip(message: lockedReason!, child: tile)
        : tile;
  }
}
