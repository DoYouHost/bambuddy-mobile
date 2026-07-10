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

/// 2-column grid of temperature gauge tiles.
class _TempGrid extends StatelessWidget {
  const _TempGrid({required this.readings});

  final List<_TempReading> readings;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 8.0;
        final tileWidth = (constraints.maxWidth - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final r in readings)
              SizedBox(width: tileWidth, child: _GaugeTile(reading: r)),
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
  const _FansGrid({required this.status});

  final PrinterStatus status;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);

    final cells = <Widget>[
      if (status.coolingFanSpeed != null)
        _FanCell(
          label: l10n.ctrlFanPartShort,
          value: status.coolingFanSpeed!,
          tokens: t,
        ),
      if (status.bigFan1Speed != null)
        _FanCell(
          label: l10n.ctrlFanAuxShort,
          value: status.bigFan1Speed!,
          tokens: t,
        ),
      if (status.bigFan2Speed != null)
        _FanCell(
          label: l10n.ctrlFanChamberShort,
          value: status.bigFan2Speed!,
          tokens: t,
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

class _FanCell extends StatelessWidget {
  const _FanCell({
    required this.label,
    required this.value,
    required this.tokens,
  });

  final String label;
  final int value;
  final DashTokens tokens;

  @override
  Widget build(BuildContext context) {
    // Spinning fan gets the cool blue accent; idle stays neutral.
    final valueColor = value > 0 ? tokens.accentBlue : tokens.textPrimary;
    return Container(
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
            '$value%',
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
  }
}
