part of 'printer_card.dart';

/// Connectivity metadata row: Wi-Fi signal, door state. Printer model intentionally
/// omitted—printer name in header suffices for identification.
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.status});

  final PrinterStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final dbm = status.wifiSignal;
    final doorOpen = status.doorOpen;

    final items = <Widget>[
      if (dbm != null)
        _InfoChip(
          icon: _wifiIcon(dbm),
          text: '$dbm dBm',
          color: _wifiColor(scheme, dbm),
        ),
      if (doorOpen != null)
        _InfoChip(
          icon: doorOpen ? Icons.meeting_room : Icons.meeting_room_outlined,
          text: doorOpen ? l10n.doorOpen : l10n.doorClosed,
          // Open door highlighted in warning color; closed shown neutrally.
          color: doorOpen ? const Color(0xFFFFB300) : scheme.onSurfaceVariant,
        ),
    ];
    if (items.isEmpty) return const SizedBox.shrink();

    // Distributed across full width (like fan chips)—clear, readable fields instead of tiny gray text.
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: items[i]),
        ],
      ],
    );
  }

  /// Wi-Fi icon based on signal strength (dBm): closer to 0 is better.
  IconData _wifiIcon(int dbm) {
    if (dbm >= -55) return Icons.network_wifi;
    if (dbm >= -65) return Icons.network_wifi_3_bar;
    if (dbm >= -75) return Icons.network_wifi_2_bar;
    return Icons.network_wifi_1_bar;
  }

  /// Color based on signal quality: good → green, fair → amber, weak → error.
  Color _wifiColor(ColorScheme scheme, int dbm) {
    if (dbm >= -60) return const Color(0xFF66BB6A);
    if (dbm >= -72) return const Color(0xFFFFB300);
    return scheme.error;
  }
}

/// Readable metadata "pill": colored icon + text on container background,
/// stretched to equal width share within a row.
class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = color ?? scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: accent),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Firmware version under printer name (visible without expanding details,
/// only when online). When update available—highlighted in tertiary color, bold,
/// with update icon and target version (`current → latest`); when current—neutral.
/// Tooltip explains state and carries release notes if server provides them.
/// Auto-hides when no firmware data. Update action will come in future (repo ready).
class _FirmwareLine extends ConsumerWidget {
  const _FirmwareLine({required this.printerId});

  final int printerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(printerFirmwareProvider(printerId));
    if (info == null || !info.hasVersion) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final update =
        info.updateAvailable && (info.latestVersion?.isNotEmpty ?? false);
    final color = update ? scheme.tertiary : scheme.onSurfaceVariant;
    final text = update
        ? '${info.currentVersion} → ${info.latestVersion}'
        : info.currentVersion!;
    final tooltip = update
        ? l10n.firmwareUpdateAvailable(info.latestVersion!)
        : l10n.firmwareUpToDate;
    final notes = info.releaseNotes?.trim();

    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Tooltip(
        message: update && notes != null && notes.isNotEmpty
            ? '$tooltip\n\n$notes'
            : tooltip,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              update ? Icons.system_update : Icons.memory,
              size: 13,
              color: color,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: color,
                  fontWeight: update ? FontWeight.w600 : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Total print time (hours, from maintenance review) under printer name.
/// Data is historical and independent of WS, so we show it even when offline.
/// Auto-hides when server provides no maintenance data.
class _TotalPrintTimeLine extends ConsumerWidget {
  const _TotalPrintTimeLine({required this.printerId});

  final int printerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hours = ref.watch(printerTotalPrintHoursProvider(printerId));
    if (hours == null || hours <= 0) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history, size: 13, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              l10n.maintenanceTotalHours(hours.round()),
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
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

/// Active print panel: name, progress bar with %, ETA, and layer count.
class _PrintPanel extends StatelessWidget {
  const _PrintPanel({required this.status});

  final PrinterStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
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

    // Row 1: file name + (when preparing) stage name.
    final nameBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (name != null)
          Text(
            name,
            style: theme.textTheme.bodyMedium,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        if (showStage) ...[
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.autorenew, size: 14, color: scheme.primary),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  stage,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.primary,
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: thumbnail + file name.
          Row(
            children: [
              // Thumbnail always during print; without cover (or in calibration
              // which has no cover)—placeholder instead of blank space.
              _CoverThumbnail(
                coverUrl: status.isCalibration ? null : status.coverUrl,
              ),
              const SizedBox(width: 12),
              Expanded(child: nameBlock),
            ],
          ),
          const SizedBox(height: 10),
          // Row 2: progress bar + rest—full width, from left edge.
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    // Prep phase → indeterminate bar (no 0%).
                    value: showStage
                        ? null
                        : (progress == null
                              ? null
                              : (progress / 100).clamp(0.0, 1.0)),
                    minHeight: 6,
                  ),
                ),
              ),
              if (progress != null && !showStage) ...[
                const SizedBox(width: 10),
                Text(
                  '${progress.toStringAsFixed(0)}%',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 14, runSpacing: 4, children: meta),
          ],
        ],
      ),
    );
  }
}

class _MetaItem extends StatelessWidget {
  const _MetaItem({required this.icon, required this.text, this.onTap});

  final IconData icon;
  final String text;

  /// When set, the item becomes tappable (e.g. AMS humidity/temp → history).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(text, style: theme.textTheme.bodySmall?.copyWith(color: color)),
      ],
    );
    if (onTap == null) return row;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: row,
      ),
    );
  }
}

/// Cover thumbnail for current print. Fetches image from `cover_url`
/// with camera stream token (`?token=`). Placeholder instead of
/// error—never crashes the card.
///
/// M2: proactive token refresh and reactive invalidation on 401
/// (`ref.invalidate(cameraTokenProvider)`) will arrive with camera preview.
class _CoverThumbnail extends ConsumerWidget {
  const _CoverThumbnail({required this.coverUrl});

  /// `null`/empty → immediate placeholder (e.g., calibration with no cover).
  final String? coverUrl;

  static const _size = 64.0;

  /// Placeholder graphic (nozzle over table, rounded transparent corners)—
  /// shown instead of cover when preview missing or calibration running.
  static const _placeholderAsset = 'assets/icons/cover_placeholder.png';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget placeholder() => Image.asset(
      _placeholderAsset,
      key: const ValueKey('cover_placeholder'),
      width: _size,
      height: _size,
      fit: BoxFit.cover,
    );

    final url = coverUrl;
    if (url == null || url.isEmpty) return placeholder();

    final baseUrl = ref.watch(serverProfileProvider)?.baseUrl;
    if (baseUrl == null) return placeholder();

    return ref
        .watch(cameraTokenProvider)
        .when(
          loading: placeholder,
          error: (_, _) => placeholder(),
          data: (token) => ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(
              '$baseUrl$url?token=$token',
              key: const ValueKey('cover_network'),
              width: _size,
              height: _size,
              // Server serves a full-res render for a 64dp tile — cap decode
              // resolution so an active print doesn't repeatedly spike memory.
              cacheWidth:
                  (_size * MediaQuery.devicePixelRatioOf(context)).round(),
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => placeholder(),
              loadingBuilder: (_, child, progress) =>
                  progress == null ? child : placeholder(),
            ),
          ),
        );
  }
}

/// Grid of temperature tiles (2 per row), each with icon and pair
/// current value / target value.
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
              SizedBox(
                width: tileWidth,
                child: _TempTile(reading: r),
              ),
          ],
        );
      },
    );
  }
}
