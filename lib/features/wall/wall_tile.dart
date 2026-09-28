import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../../core/format/duration_format.dart';
import '../../core/models/printer_status.dart';
import '../../core/notifications/hms_catalog.dart';
import '../../core/printers/offline_debounce.dart';
import '../../core/theme/dash_theme.dart';
import '../../data/printers_repository.dart';
import '../common/dash_progress_bar.dart';
import '../../l10n/app_localizations.dart';

/// One printer on the wall: name, state, progress, time left, layer, the first
/// active fault, or that the printer is gone (docs/tv-flavor.md §13.1).
///
/// Offline follows the printer card's rule ([OfflineDebounce]), so the wall and
/// the dashboard beneath it never disagree about the same printer.
class WallTile extends StatefulWidget {
  const WallTile({super.key, required this.item, this.inTouchSince});

  final PrinterWithStatus item;

  /// When the line to the server came up — see `PrinterCard.inTouchSince`.
  final DateTime? inTouchSince;

  @override
  State<WallTile> createState() => _WallTileState();
}

class _WallTileState extends State<WallTile> {
  final _debounce = OfflineDebounce();

  // No status at all is the roster without a frame: unreachable, as the
  // printer card reads it.
  bool? _reachability(PrinterStatus? status) =>
      status == null ? false : status.connected;

  @override
  void initState() {
    super.initState();
    _debounce.seed(_reachability(widget.item.status));
  }

  @override
  void didUpdateWidget(WallTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final since = widget.inTouchSince;
    _debounce.observe(
      _reachability(widget.item.status),
      debounce:
          since == null || clock.now().difference(since) >= _debounce.window,
      onSustained: () {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  void dispose() {
    _debounce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final status = widget.item.status;
    final offline = _debounce.offline;
    final fault = offline
        ? null
        : firstDisplayableHmsError(
            status,
            describe: HmsCatalog.instance.describe,
          );
    final printing = !offline && (status?.isPrinting ?? false);
    final progress = status?.progress;

    return Container(
      decoration: t.cardBox.copyWith(
        border: fault == null ? null : Border.all(color: t.danger, width: 2),
      ),
      padding: const EdgeInsets.all(12),
      child: Opacity(
        opacity: offline ? 0.55 : 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.item.printer.name,
                    style: t.titleMd,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                _statePill(t, l10n, status, offline),
              ],
            ),
            if (fault != null) ...[
              const SizedBox(height: 6),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: DashPill(
                  label: fault.shortCode ?? l10n.hmsErrorsCount(1),
                  accent: t.danger,
                  accentInk: t.dangerInk,
                  icon: Icons.error_outline_rounded,
                  dense: true,
                ),
              ),
            ],
            Expanded(
              child: Center(
                child: offline
                    ? Icon(
                        Icons.cloud_off_rounded,
                        size: 32,
                        color: t.textTertiary,
                      )
                    : printing && progress != null
                    ? FittedBox(
                        child: Text(
                          '${progress.toStringAsFixed(0)}%',
                          style: t.monoDisplay.copyWith(fontSize: 40),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
            if (printing) ...[
              DashProgressBar(
                value: progress == null
                    ? null
                    : (progress / 100).clamp(0.0, 1.0),
                height: 4,
                radius: 2,
                color: status!.isPaused ? t.accentOrange : null,
              ),
              const SizedBox(height: 6),
              _meta(t, l10n, status),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statePill(
    DashTokens t,
    AppLocalizations l10n,
    PrinterStatus? status,
    bool offline,
  ) {
    if (offline) {
      return DashPill(
        label: l10n.statusOffline,
        accent: t.danger,
        accentInk: t.dangerInk,
        dense: true,
      );
    }
    final label = (status?.state ?? l10n.statusUnavailable).toUpperCase();
    if (status?.isPaused ?? false) {
      return DashPill(
        label: label,
        accent: t.accentOrange,
        accentInk: t.accentOrangeInk,
        dense: true,
      );
    }
    if (status?.isPrinting ?? false) {
      return DashPill(
        label: label,
        accent: t.accentGreen,
        accentInk: t.accentGreenInk,
        dense: true,
      );
    }
    return DashPill(label: label, accent: t.textSecondary, dense: true);
  }

  Widget _meta(DashTokens t, AppLocalizations l10n, PrinterStatus status) {
    final remaining = status.remainingTime;
    final layer = status.layerNum;
    final total = status.totalLayers;
    return Wrap(
      spacing: 12,
      runSpacing: 2,
      children: [
        if (remaining != null && remaining > 0)
          Text(formatMinutes(l10n, remaining), style: t.monoValue),
        if (layer != null && total != null)
          Text('L $layer/$total', style: t.monoLabel),
      ],
    );
  }
}
