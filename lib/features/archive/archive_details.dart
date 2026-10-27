import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:app_util/app_util.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/datetime_format.dart';
import '../../core/format/duration_format.dart';
import '../../core/models/archive.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common/web_link.dart';
import 'archive_providers.dart';

/// The printer a print ran on, by name, as the web card's `printerMap` lookup —
/// or the model it was sliced for when that printer is gone or was never set.
String? archivePrinterLabel(Archive archive, Map<int, String> names) =>
    names[archive.printerId] ?? archive.slicedForModel;

final archivePrinterNamesProvider = Provider.autoDispose<Map<int, String>>(
  (ref) => {
    for (final p in ref.watch(printersForPickerProvider).value ?? [])
      p.id: p.name,
  },
);

/// Grams as the web card prints them, to one decimal.
String archiveGrams(double grams) => '${grams.toStringAsFixed(1)} g';

/// Money as the web card prints it, always to two decimals.
String archiveMoney(String currency, double amount) =>
    formatMoney(currency, amount.toStringAsFixed(2));

/// The time badge's text and tone, `time_accuracy - 100` signed: green within
/// ±5 %, blue when the print beat the estimate, orange when it ran over — the
/// web card's thresholds.
({String text, Color fill, Color ink}) timeAccuracyBadge(
  DashTokens t,
  double accuracy,
) {
  final delta = (accuracy - 100).toStringAsFixed(0);
  final text = '${accuracy > 100 ? '+' : ''}$delta%';
  if (accuracy >= 95 && accuracy <= 105) {
    return (text: text, fill: t.accentGreen, ink: t.accentGreenInk);
  }
  return accuracy > 105
      ? (text: text, fill: t.accentBlue, ink: t.accentBlue)
      : (text: text, fill: t.accentOrange, ink: t.accentOrangeInk);
}

/// A filament colour as a small round mark. The outline keeps black and white
/// filament visible on either theme.
class FilamentDot extends StatelessWidget {
  const FilamentDot({super.key, required this.hex});

  final String hex;

  static const size = 10.0;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colorFromHex(hex),
        shape: BoxShape.circle,
        border: Border.all(color: t.textTertiary),
      ),
    );
  }
}

/// The list row under the title: where and when it printed, then what it printed
/// with. The first line breaks only between its facts, never inside one, and
/// takes a second line before it gives anything up. A long material list is the
/// one part of the second that gives way; the weight after it stays.
class ArchiveRowMeta extends ConsumerWidget {
  const ArchiveRowMeta({super.key, required this.archive});

  final Archive archive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final printer = archivePrinterLabel(
      archive,
      ref.watch(archivePrinterNamesProvider),
    );
    final seconds = archive.shownTimeSeconds;
    final where = <String>[
      ?printer,
      if (seconds != null && seconds > 0) formatSeconds(l10n, seconds),
      if (archive.createdAt != null)
        DateTimeFormats.of(context).date(archive.createdAt!),
    ];
    final colours = archive.filamentColors;
    // Empty and zero say nothing, as on the web card, whose checks are truthy.
    final material = (archive.filamentType ?? '').isEmpty
        ? null
        : archive.filamentType;
    final grams = (archive.filamentUsedGrams ?? 0) > 0
        ? archive.filamentUsedGrams
        : null;
    final style = t.monoLabel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (where.isNotEmpty)
          Text(
            // A no-break space inside each fact, so a wrap lands on a separator.
            where.map((f) => f.replaceAll(' ', '\u00A0')).join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        if (colours.isNotEmpty || material != null || grams != null)
          Row(
            children: [
              for (final hex in colours.take(_maxDots)) ...[
                FilamentDot(hex: hex),
                const SizedBox(width: DashSpace.xs),
              ],
              if (material != null)
                Flexible(
                  child: Text(
                    material,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style,
                  ),
                ),
              if (grams != null)
                Text(
                  material == null
                      ? archiveGrams(grams)
                      : ' · ${archiveGrams(grams)}',
                  maxLines: 1,
                  style: style,
                ),
            ],
          ),
      ],
    );
  }

  /// Past this the row would spend its width on dots; the sheet lists them all.
  static const _maxDots = 4;
}

/// Small labelled marks under the sheet's title: printer, file kind, project,
/// how many times it ran.
class ArchiveHeaderChips extends ConsumerWidget {
  const ArchiveHeaderChips({super.key, required this.archive});

  final Archive archive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final printer = archivePrinterLabel(
      archive,
      ref.watch(archivePrinterNamesProvider),
    );
    final project = archive.projectName;
    return Wrap(
      spacing: DashSpace.xs,
      runSpacing: DashSpace.xs,
      children: [
        if (printer != null) _Chip(text: printer, ink: t.textSecondary),
        archive.isSliced
            ? _Chip(text: l10n.archiveFileTypeGcode, ink: t.accentGreenInk)
            : _Chip(text: l10n.archiveFileTypeSource, ink: t.accentOrangeInk),
        if (project != null && project.isNotEmpty)
          _Chip(text: project, ink: t.accentBlue),
        if (archive.runCount > 1)
          _Chip(
            text: l10n.archiveRunCount(archive.runCount),
            ink: t.accentOrangeInk,
          ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.ink});

  final String text;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: DashSpace.sm),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ink.withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: t.micro.copyWith(color: ink),
      ),
    );
  }
}

/// The web card's stats grid: time, layers, objects and the model it was
/// sliced for in two columns, then the cost and the filaments across the full
/// width. Each item is left out when the server did not send it, and the panel
/// with them when none came.
class ArchiveStatsPanel extends ConsumerWidget {
  const ArchiveStatsPanel({super.key, required this.archive});

  final Archive archive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final cells = <Widget>[?_time(t, l10n), ?_layers(t, l10n)];
    final objects = archive.objectCount;
    if (objects != null && objects > 0) {
      cells.add(
        _Stat(
          icon: Icons.category_outlined,
          text: l10n.archiveObjectCount(objects),
        ),
      );
    }
    final model = archive.slicedForModel;
    if (model != null && model.isNotEmpty) {
      cells.add(
        Semantics(
          label: l10n.archiveSlicedFor(model),
          excludeSemantics: true,
          child: _Stat(icon: Icons.print_outlined, text: model),
        ),
      );
    }
    final cost = _cost(context, ref, t, l10n);
    final filament = _filament(t, l10n);
    if (cells.isEmpty && cost == null && filament == null) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.only(bottom: DashSpace.sm),
      padding: const EdgeInsets.all(DashSpace.md),
      decoration: BoxDecoration(
        color: t.subCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.subCardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DashSpace.sm,
        children: [
          for (var i = 0; i < cells.length; i += 2)
            Row(
              children: [
                Expanded(child: cells[i]),
                const SizedBox(width: DashSpace.md),
                Expanded(
                  child: i + 1 < cells.length
                      ? cells[i + 1]
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ?cost,
          ?filament,
        ],
      ),
    );
  }

  Widget? _time(DashTokens t, AppLocalizations l10n) {
    final shown = archive.shownTimeSeconds;
    if (shown == null || shown <= 0) return null;
    final accuracy = archive.timeAccuracy;
    final estimated = archive.printTimeSeconds;
    final actual = archive.actualTimeSeconds;
    final badge = accuracy == null ? null : timeAccuracyBadge(t, accuracy);
    final row = Row(
      children: [
        Icon(Icons.schedule, size: _iconSize, color: t.textTertiary),
        const SizedBox(width: DashSpace.sm),
        Flexible(
          child: Text(
            formatSeconds(l10n, shown),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.monoValue,
          ),
        ),
        if (badge != null) ...[
          const SizedBox(width: DashSpace.xs),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: DashSpace.xs),
            decoration: BoxDecoration(
              color: badge.fill.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              badge.text,
              style: t.monoMicro.copyWith(color: badge.ink),
            ),
          ),
        ],
      ],
    );
    if (estimated == null || actual == null) return row;
    return Tooltip(
      message: l10n.archiveTimeDetail(
        formatSeconds(l10n, estimated),
        formatSeconds(l10n, actual),
      ),
      triggerMode: TooltipTriggerMode.tap,
      child: row,
    );
  }

  Widget? _layers(DashTokens t, AppLocalizations l10n) {
    final layers = archive.totalLayers;
    final height = archive.layerHeight;
    final parts = [
      if (layers != null && layers > 0) l10n.archiveLayerCount(layers),
      if (height != null && height > 0) '${_trimZeros(height)} mm',
    ];
    if (parts.isEmpty) return null;
    return _Stat(icon: Icons.layers_outlined, text: parts.join(' · '));
  }

  /// The sum first, then each part spread across the line by its icon alone —
  /// the label is in the tooltip and for a screen reader. A single part needs
  /// no breakdown of itself.
  Widget? _cost(
    BuildContext context,
    WidgetRef ref,
    DashTokens t,
    AppLocalizations l10n,
  ) {
    final total = archive.totalCost;
    if (total == null) return null;
    final currency = ref.watch(currencySymbolProvider);
    final kwh = archive.energyKwh;
    final parts = [
      if (archive.cost case final v?)
        (Icons.toll_outlined, l10n.statsFilamentCost, v, null),
      if (archive.energyCost case final v?)
        (
          Icons.bolt,
          l10n.statsEnergyCost,
          v,
          kwh == null
              ? null
              : '${l10n.statsEnergyUsed}: ${kwh.toStringAsFixed(3)} kWh',
        ),
      if (archive.wearCost case final v?)
        (Icons.build_outlined, l10n.statsWearCost, v, null),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DashSpace.xs,
      children: [
        Row(
          children: [
            Expanded(child: Text(l10n.archivePrintCost, style: t.labelSoft)),
            Text(archiveMoney(currency, total), style: t.monoTitle),
          ],
        ),
        if (parts.length > 1)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final (icon, label, value, detail) in parts)
                Tooltip(
                  message: detail ?? label,
                  triggerMode: TooltipTriggerMode.tap,
                  child: Semantics(
                    label: '$label ${archiveMoney(currency, value)}',
                    excludeSemantics: true,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: _iconSize, color: t.textTertiary),
                        const SizedBox(width: DashSpace.xs),
                        Text(
                          archiveMoney(currency, value),
                          style: t.monoLabel.copyWith(color: t.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  /// One line per AMS slot when the server kept the slicer's per-slot usage;
  /// otherwise the web's materials-and-dots, where nothing pairs a colour with
  /// its material.
  Widget? _filament(DashTokens t, AppLocalizations l10n) {
    final slots = archive.filamentSlots;
    if (slots.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DashSpace.xs,
        children: [
          for (final s in slots)
            Row(
              children: [
                FilamentDot(hex: s.color),
                const SizedBox(width: DashSpace.sm),
                Flexible(
                  child: Text(
                    s.type,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.body,
                  ),
                ),
                const SizedBox(width: DashSpace.sm),
                Text(l10n.archiveSlot(s.slot), style: t.labelSoft),
                const Spacer(),
                Text(archiveGrams(s.grams), style: t.monoValue),
              ],
            ),
        ],
      );
    }
    final material = archive.filamentType;
    if (material == null || material.isEmpty) return null;
    return Row(
      children: [
        Flexible(
          child: Text(
            material,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.body,
          ),
        ),
        const SizedBox(width: DashSpace.sm),
        Flexible(
          child: Wrap(
            spacing: DashSpace.xs,
            runSpacing: DashSpace.xs,
            children: [
              for (final hex in archive.filamentColors) FilamentDot(hex: hex),
            ],
          ),
        ),
      ],
    );
  }

  static const _iconSize = 16.0;
}

String _trimZeros(double v) =>
    v.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Row(
      children: [
        Icon(icon, size: ArchiveStatsPanel._iconSize, color: t.textTertiary),
        const SizedBox(width: DashSpace.sm),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.body,
          ),
        ),
      ],
    );
  }
}

/// Tags and the note, as the web card shows them under the stats.
class ArchiveTagsAndNote extends StatelessWidget {
  const ArchiveTagsAndNote({super.key, required this.archive});

  final Archive archive;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final tags = archive.tagList;
    final note = archive.notes?.trim() ?? '';
    if (tags.isEmpty && note.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: DashSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DashSpace.sm,
        children: [
          if (tags.isNotEmpty)
            Wrap(
              spacing: DashSpace.xs,
              runSpacing: DashSpace.xs,
              children: [
                for (final tag in tags) _Chip(text: tag, ink: t.textSecondary),
              ],
            ),
          if (note.isNotEmpty) Text(note, style: t.bodySoft),
        ],
      ),
    );
  }
}

/// Date, who uploaded it and the file size, under a hairline.
class ArchiveFooter extends StatelessWidget {
  const ArchiveFooter({super.key, required this.archive});

  final Archive archive;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final left = [
      if (archive.createdAt != null)
        DateTimeFormats.of(context).dateTime(archive.createdAt!),
      ?archive.createdByUsername,
    ];
    final size = archive.fileSize;
    if (left.isEmpty && size == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: DashSpace.sm),
      padding: const EdgeInsets.only(top: DashSpace.sm),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.hairline)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              left.join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.labelSoft,
            ),
          ),
          if (size != null) Text(formatBytes(size), style: t.monoLabel),
        ],
      ),
    );
  }
}

/// The web card's globe: the user's own link, else the MakerWorld page.
/// Absent when there is neither.
class ArchiveLinkButton extends StatelessWidget {
  const ArchiveLinkButton({super.key, required this.archive});

  final Archive archive;

  @override
  Widget build(BuildContext context) {
    final link = archive.link;
    if (link == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: DashSpace.sm),
      child: SizedBox(
        width: double.infinity,
        child: logTag(
          'archive.open_link',
          OutlinedButton.icon(
            icon: const Icon(Icons.public),
            label: Text(AppLocalizations.of(context).archiveOpenLink),
            onPressed: () => openWebLink(context, link),
          ),
        ),
      ),
    );
  }
}
