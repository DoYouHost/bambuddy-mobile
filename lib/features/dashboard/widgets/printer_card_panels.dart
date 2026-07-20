part of 'printer_card.dart';

/// Connectivity row (design "network & door"): a hairline top border with Wi-Fi
/// signal on the left and door state on the right, in mono type. Auto-hides when
/// the server provides neither reading.
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.status});

  final PrinterStatus status;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final dbm = status.wifiSignal;
    final doorOpen = status.doorOpen;
    if (dbm == null && doorOpen == null) return const SizedBox.shrink();

    Widget item(IconData icon, String text, Color color) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              text,
              style: TextStyle(
                fontFamily: DashTokens.fontMono,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        );

    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.hairline)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (dbm != null)
            item(_wifiIcon(dbm), '$dbm dBm',
                _wifiColor(t, Theme.of(context).colorScheme, dbm))
          else
            const SizedBox.shrink(),
          if (doorOpen != null)
            item(
              doorOpen ? Icons.meeting_room : Icons.meeting_room_outlined,
              (doorOpen ? l10n.doorOpen : l10n.doorClosed).toUpperCase(),
              doorOpen ? t.accentOrange : t.textTertiary,
            )
          else
            const SizedBox.shrink(),
        ],
      ),
    );
  }

  /// Wi-Fi icon based on signal strength (dBm): closer to 0 is better.
  IconData _wifiIcon(int dbm) {
    if (dbm >= -55) return Icons.network_wifi;
    if (dbm >= -65) return Icons.network_wifi_3_bar;
    if (dbm >= -75) return Icons.network_wifi_2_bar;
    return Icons.network_wifi_1_bar;
  }

  /// Color by quality: good → green accent, fair → orange, weak → error.
  Color _wifiColor(DashTokens t, ColorScheme scheme, int dbm) {
    if (dbm >= -60) return t.accentGreenInk;
    if (dbm >= -72) return t.accentOrange;
    return scheme.error;
  }
}

/// Firmware version under printer name (visible without expanding details).
/// When an update is available — accent-colored with target version
/// (`current → latest`); otherwise neutral mono. Auto-hides without data.
class _FirmwareLine extends ConsumerWidget {
  const _FirmwareLine({required this.printerId});

  final int printerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(printerFirmwareProvider(printerId));
    if (info == null || !info.hasVersion) return const SizedBox.shrink();

    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final update =
        info.updateAvailable && (info.latestVersion?.isNotEmpty ?? false);
    final color = update ? t.accentGreenInk : t.textTertiary;
    final text = update
        ? '${info.currentVersion} → ${info.latestVersion}'
        : info.currentVersion!;
    final tooltip = update
        ? l10n.firmwareUpdateAvailable(info.latestVersion!)
        : l10n.firmwareUpToDate;
    final notes = info.releaseNotes?.trim();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Tooltip(
        message: update && notes != null && notes.isNotEmpty
            ? '$tooltip\n\n$notes'
            : tooltip,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (update) ...[
              Icon(Icons.system_update, size: 12, color: color),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: DashTokens.fontMono,
                  fontSize: 11.5,
                  fontWeight: update ? FontWeight.w700 : FontWeight.w600,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Total print time (hours) under printer name — historical, shown even offline.
/// Rendered inline after firmware with a mono middle dot. Auto-hides without data.
class _TotalPrintTimeLine extends ConsumerWidget {
  const _TotalPrintTimeLine({required this.printerId});

  final int printerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hours = ref.watch(printerTotalPrintHoursProvider(printerId));
    if (hours == null || hours <= 0) return const SizedBox.shrink();

    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        l10n.maintenanceTotalHours(hours.round()),
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: DashTokens.fontMono,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: t.textTertiary,
        ),
      ),
    );
  }
}

/// Parses filament color from hex RRGGBBAA to [Color]; null if invalid.
Color? _parseTrayColor(String? hex) {
  if (hex == null || hex.length != 8) return null;
  final rgb = int.tryParse(hex.substring(0, 6), radix: 16);
  final a = int.tryParse(hex.substring(6, 8), radix: 16);
  if (rgb == null || a == null) return null;
  return Color((a << 24) | rgb);
}

/// Active print panel: cover, name, progress bar with %, ETA, and layer count.
/// Restyled to a dark sub-card in the modernized card.
class _PrintPanel extends StatelessWidget {
  const _PrintPanel({required this.status});

  final PrinterStatus status;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final progress = status.progress;
    final name = status.currentPrint ?? status.gcodeFile;

    final remaining = status.remainingTime;
    final meta = <Widget>[
      if (remaining != null && remaining > 0)
        _MetaItem(
          icon: Icons.schedule,
          text: l10n.remaining(_durationText(l10n, remaining)),
        ),
      if (remaining != null && remaining > 0)
        _MetaItem(
          icon: Icons.flag_outlined,
          text: l10n.eta(_etaTime(remaining)),
        ),
      if (status.layerNum != null && status.totalLayers != null)
        _MetaItem(
          icon: Icons.layers_outlined,
          text: '${status.layerNum}/${status.totalLayers}',
        ),
    ];

    // Prep phase (heating, auto bed leveling): show stage name
    // and indeterminate bar instead of confusing 0%.
    final stage = status.stgCurName?.trim();
    final showStage = status.isPreparing && stage != null && stage.isNotEmpty;

    final nameBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (name != null)
          Text(
            name,
            style: TextStyle(
              fontFamily: DashTokens.fontUi,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: t.textPrimary,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        if (showStage) ...[
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.autorenew, size: 14, color: t.accentGreenInk),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  stage,
                  style: TextStyle(
                    fontFamily: DashTokens.fontUi,
                    fontSize: 11.5,
                    color: t.accentGreenInk,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ],
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.subCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.subCardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _CoverThumbnail(
                coverUrl: status.isCalibration ? null : status.coverUrl,
              ),
              const SizedBox(width: 12),
              Expanded(child: nameBlock),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: showStage
                        ? null
                        : (progress == null
                            ? null
                            : (progress / 100).clamp(0.0, 1.0)),
                    minHeight: 6,
                    backgroundColor: t.gaugeTrack,
                    valueColor: AlwaysStoppedAnimation(t.accentGreen),
                  ),
                ),
              ),
              if (progress != null && !showStage) ...[
                const SizedBox(width: 10),
                Text(
                  '${progress.toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontFamily: DashTokens.fontMono,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: t.textPrimary,
                  ),
                ),
              ],
            ],
          ),
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 14, runSpacing: 6, children: meta),
          ],
        ],
      ),
    );
  }
}

/// Print-panel metadata item (remaining/ETA/layers): mono text with a leading icon.
class _MetaItem extends StatelessWidget {
  const _MetaItem({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: t.textSecondary),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontFamily: DashTokens.fontMono,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: t.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// Cover thumbnail for the current print (fetched with the camera stream token).
/// Placeholder instead of error — never crashes the card.
class _CoverThumbnail extends ConsumerStatefulWidget {
  const _CoverThumbnail({required this.coverUrl});

  final String? coverUrl;

  static const _size = 64.0;
  static const _placeholderAsset = 'assets/icons/cover_placeholder.png';

  @override
  ConsumerState<_CoverThumbnail> createState() => _CoverThumbnailState();
}

class _CoverThumbnailState extends ConsumerState<_CoverThumbnail>
    with CameraTokenImageRecovery {
  @override
  Widget build(BuildContext context) {
    Widget placeholder() => ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.asset(
            _CoverThumbnail._placeholderAsset,
            key: const ValueKey('cover_placeholder'),
            width: _CoverThumbnail._size,
            height: _CoverThumbnail._size,
            fit: BoxFit.cover,
          ),
        );

    final url = widget.coverUrl;
    if (url == null || url.isEmpty) return placeholder();

    final baseUrl = ref.watch(serverProfileProvider)?.baseUrl;
    if (baseUrl == null) return placeholder();

    return ref.watch(cameraTokenProvider).when(
          loading: placeholder,
          error: (_, _) => placeholder(),
          data: (token) => ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(
              '$baseUrl$url?token=$token',
              key: const ValueKey('cover_network'),
              width: _CoverThumbnail._size,
              height: _CoverThumbnail._size,
              cacheWidth: (_CoverThumbnail._size *
                      MediaQuery.devicePixelRatioOf(context))
                  .round(),
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, error, _) {
                recoverCameraTokenOnError(error, token);
                return placeholder();
              },
              loadingBuilder: (_, child, progress) =>
                  progress == null ? child : placeholder(),
            ),
          ),
        );
  }
}

/// 2-column grid of temperature gauge tiles. Tiles are tappable to set targets
/// (see [_GaugeTile]); [printerId]/[model] are threaded down for the command
/// and capability gating.
class _TempGrid extends StatelessWidget {
  const _TempGrid({
    required this.readings,
    required this.printerId,
    required this.model,
    required this.activeExtruder,
    required this.printing,
  });

  final List<_TempReading> readings;
  final int printerId;
  final String? model;
  final int? activeExtruder;
  final bool printing;

  @override
  Widget build(BuildContext context) {
    // Dual-head printers (H2D/X2D) report a second nozzle as `nozzle_2` (RIGHT)
    // while the plain `nozzle` key is the LEFT one. Map each to the server's
    // hardware index (0=right/default, 1=left). On single-nozzle machines the
    // plain `nozzle` is the default → index 0.
    final hasSecondNozzle =
        readings.any((r) => r.kind == _TempKind.nozzle && r.index != null);

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 8.0;
        final tileWidth = (constraints.maxWidth - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final r in readings)
              SizedBox(
                width: tileWidth,
                child: _GaugeTile(
                  reading: r,
                  printerId: printerId,
                  model: model,
                  nozzleIndex: r.kind != _TempKind.nozzle
                      ? null
                      : (r.index != null ? 0 : (hasSecondNozzle ? 1 : 0)),
                  dualNozzle: hasSecondNozzle,
                  activeExtruder: activeExtruder,
                  printing: printing,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Always-visible fan readings as a 3-column grid (Hotend / Aux / Chamber),
/// matching the design. Each cell shows the fan's short label and % in mono.
/// Renders only when the server provides at least one fan reading.
class _FansGrid extends StatelessWidget {
  const _FansGrid({required this.status, required this.printerId});

  final PrinterStatus status;
  final int printerId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // Fan id → server key mapping mirrors the backend fan-speed route:
    // part=cooling, aux=big fan 1, chamber=big fan 2.
    final cells = <Widget>[
      if (status.coolingFanSpeed != null)
        _FanCell(
          fan: 'part',
          label: l10n.ctrlFanPartShort,
          sheetLabel: l10n.ctrlFanPart,
          value: status.coolingFanSpeed!,
          printerId: printerId,
        ),
      if (status.bigFan1Speed != null)
        _FanCell(
          fan: 'aux',
          label: l10n.ctrlFanAuxShort,
          sheetLabel: l10n.ctrlFanAux,
          value: status.bigFan1Speed!,
          printerId: printerId,
        ),
      if (status.bigFan2Speed != null)
        _FanCell(
          fan: 'chamber',
          label: l10n.ctrlFanChamberShort,
          sheetLabel: l10n.ctrlFanChamber,
          value: status.bigFan2Speed!,
          printerId: printerId,
        ),
    ];
    if (cells.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          for (var i = 0; i < cells.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: cells[i]),
          ],
        ],
      ),
    );
  }
}

class _FanCell extends ConsumerWidget {
  const _FanCell({
    required this.fan,
    required this.label,
    required this.sheetLabel,
    required this.value,
    required this.printerId,
  });

  /// Fan id sent to the server ('part'/'aux'/'chamber').
  final String fan;
  final String label;
  final String sheetLabel;
  final int value;
  final int printerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = DashTokens.of(context);
    final pending =
        ref.watch(controlsProvider.select((s) => s.pendingFor(printerId)));
    final forbidden = ref.watch(controlsProvider.select((s) => s.forbidden));
    // Optimistic overlay until real status catches up.
    final shown = pending.fanSpeed(fan) ?? value;
    // Spinning fan gets the cool blue accent; idle stays neutral.
    final valueColor = shown > 0 ? tokens.accentBlue : tokens.textPrimary;

    final cell = Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: tokens.subCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.subCardBorder),
      ),
      child: Column(
        children: [
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: DashTokens.fontUi,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: tokens.textTertiary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '$shown%',
            style: TextStyle(
              fontFamily: DashTokens.fontMono,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: valueColor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );

    if (forbidden) return cell;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => _FanControlSheet(
            printerId: printerId,
            fan: fan,
            label: sheetLabel,
            initialSpeed: shown,
          ),
        ),
        child: cell,
      ),
    );
  }
}

/// Bottom sheet to set a fan's speed (%): slider with fine −/+ steppers,
/// quick-pick presets, and Off/Set. Mirrors [_TempControlSheet]; applying
/// closes the sheet and the optimistic value shows on the fan cell right away.
class _FanControlSheet extends ConsumerStatefulWidget {
  const _FanControlSheet({
    required this.printerId,
    required this.fan,
    required this.label,
    required this.initialSpeed,
  });

  final int printerId;
  final String fan;
  final String label;
  final int initialSpeed;

  @override
  ConsumerState<_FanControlSheet> createState() => _FanControlSheetState();
}

class _FanControlSheetState extends ConsumerState<_FanControlSheet> {
  static const _presets = [25, 50, 75, 100];

  late int _speed = widget.initialSpeed.clamp(0, 100);
  bool _busy = false;

  void _bump(int delta) =>
      setState(() => _speed = (_speed + delta).clamp(0, 100));

  Future<void> _apply(int speed) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    final result = await ref
        .read(controlsProvider.notifier)
        .setFanSpeed(widget.printerId, widget.fan, speed);
    if (!mounted) return;
    navigator.pop();
    final msg = switch (result) {
      ControlResult.ok => null,
      ControlResult.forbidden => l10n.ctrlForbidden,
      ControlResult.error => l10n.ctrlFailed,
    };
    if (msg != null) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final accent = _speed > 0 ? t.accentBlue : t.textSecondary;

    return SafeArea(
      top: false,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: t.overlaySurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(top: BorderSide(color: t.subCardBorder)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: t.textTertiary.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontFamily: DashTokens.fontUi,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: t.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      _speed == 0 ? l10n.ctrlOff : '$_speed%',
                      style: TextStyle(
                        fontFamily: DashTokens.fontMono,
                        fontSize: 44,
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _StepButton(icon: Icons.remove, onTap: () => _bump(-1)),
                      Expanded(
                        child: Slider(
                          value: _speed.toDouble(),
                          max: 100,
                          activeColor: accent,
                          onChanged: (v) => setState(() => _speed = v.round()),
                        ),
                      ),
                      _StepButton(icon: Icons.add, onTap: () => _bump(1)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final p in _presets)
                        _PresetChip(
                          label: '$p%',
                          selected: _speed == p,
                          onTap: () => setState(() => _speed = p),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _SheetButton(
                          label: l10n.ctrlOff,
                          onTap: _busy ? null : () => _apply(0),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _SheetButton(
                          label: l10n.ctrlSet,
                          filled: true,
                          busy: _busy,
                          onTap: _busy ? null : () => _apply(_speed),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
