import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:app_util/app_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/format/duration_format.dart';
import '../../core/models/library_file.dart';
import '../../core/models/library_folder.dart';
import '../../core/printers/gcode_compat.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import '../files/file_manager_providers.dart';
import '../files/library_thumbnail.dart';
import '../stats/stats_common.dart';
import 'controller_controls.dart';
import 'controller_providers.dart';

/// Height of a tile in the grid: its thumbnail and a margin, so a tile is a
/// touch target well above the minimum whatever it says. Three rows of them
/// fill the card of the 800x360 body.
const _tileHeight = 82.0;
const _thumbSize = 64.0;
const _columns = 2;

/// The Files tab: the server's file library, scoped to the controller's printer
/// ([docs/single-printer-controller.md]). The library is the only source a print
/// can start from — the server cannot start one from the printer's own storage.
///
/// Reads [fileManagerProvider], which the controller keeps alive while it is
/// open so the folder and the sort survive a visit to another tab.
class ControllerFiles extends ConsumerWidget {
  const ControllerFiles({super.key, required this.printerId});

  final int printerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DashTokens.of(context);
    final async = ref.watch(fileManagerProvider);
    // Kept while a refresh is under way, so the grid does not blink out.
    final state = async.valueOrNull;
    final model = ref.watch(
      controllerPrinterProvider(printerId).select((p) => p.item?.printer.model),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(state: state),
        const SizedBox(height: DashSpace.md),
        Expanded(
          child: Container(
            decoration: t.cardBox,
            padding: const EdgeInsets.all(DashSpace.sm),
            child: switch ((state, async)) {
              (final s?, _) => _Grid(
                state: s,
                printerModel: model,
                refreshing: async.isLoading,
              ),
              (_, AsyncError(:final error)) => _Failure(error: error),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ),
        ),
      ],
    );
  }
}

/// Up, where the user is, the sort, and a refresh.
class _Header extends ConsumerWidget {
  const _Header({required this.state});

  final FileManagerState? state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final s = state;
    final notifier = ref.read(fileManagerProvider.notifier);
    final folder = s?.currentFolder;
    final path = [
      l10n.fmRoot,
      for (final f in s?.breadcrumb ?? const []) f.name,
    ];
    return Row(
      children: [
        _HeaderButton(
          id: 'controller.files.up',
          tooltip: l10n.pfmUp,
          icon: Icons.arrow_upward_rounded,
          onPressed: folder == null
              ? null
              : () => notifier.openFolder(folder.parentId),
        ),
        const SizedBox(width: DashSpace.sm),
        Expanded(
          child: Container(
            height: controllerButtonHeight,
            padding: const EdgeInsets.symmetric(horizontal: DashSpace.lg),
            alignment: Alignment.centerLeft,
            decoration: t.cardBox,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    path.join('  /  '),
                    style: t.titleSm,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (s != null) ...[
                  const SizedBox(width: DashSpace.md),
                  Text(
                    _sortLabel(l10n, s.sort),
                    style: t.monoLabel,
                    maxLines: 1,
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: DashSpace.sm),
        _HeaderButton(
          id: 'controller.files.sort',
          tooltip: l10n.fmSortBy,
          icon: Icons.sort_rounded,
          // Six orders on a touch panel: one tap moves to the next, and the
          // label beside the path says which is on.
          onPressed: s == null
              ? null
              : () => notifier.setSort(
                  FileSort.values[(s.sort.index + 1) % FileSort.values.length],
                ),
        ),
        const SizedBox(width: DashSpace.sm),
        _HeaderButton(
          id: 'controller.files.refresh',
          tooltip: l10n.pfmRefreshTooltip,
          icon: Icons.refresh_rounded,
          onPressed: notifier.refresh,
        ),
      ],
    );
  }
}

String _sortLabel(AppLocalizations l10n, FileSort sort) => switch (sort) {
  FileSort.dateDesc => l10n.fmSortDateNewest,
  FileSort.dateAsc => l10n.fmSortDateOldest,
  FileSort.nameAsc => l10n.fmSortNameAZ,
  FileSort.nameDesc => l10n.fmSortNameZA,
  FileSort.sizeDesc => l10n.fmSortSizeLargest,
  FileSort.sizeAsc => l10n.fmSortSizeSmallest,
};

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.id,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String id;
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Tooltip(
      message: tooltip,
      child: logTag(
        id,
        FilledButton(
          style: controllerButtonStyle(
            t,
            minimumSize: const Size.square(controllerButtonHeight),
            padding: EdgeInsets.zero,
          ),
          onPressed: onPressed,
          child: Icon(icon),
        ),
      ),
    );
  }
}

/// Folders first, then files; what the library screen would list, in the
/// controller's tiles.
class _Grid extends ConsumerWidget {
  const _Grid({
    required this.state,
    required this.printerModel,
    required this.refreshing,
  });

  final FileManagerState state;
  final String? printerModel;
  final bool refreshing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final notifier = ref.read(fileManagerProvider.notifier);
    // A search or a tag filter spans the whole library, so the folders of the
    // directory the user stands in would be noise beside its results.
    final folders = state.isSearching || state.isTagFiltering
        ? const <LibraryFolder>[]
        : state.subfolders;
    final files = state.visibleFiles;
    if (folders.isEmpty && files.isEmpty) {
      return _Message(
        icon: Icons.folder_open_outlined,
        text:
            state.isSearching ||
                state.isTagFiltering ||
                state.typeFilter != null
            ? l10n.fmNoMatches
            : l10n.fmEmpty,
      );
    }
    return Column(
      children: [
        if (refreshing) const LinearProgressIndicator(),
        Expanded(
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _columns,
              mainAxisExtent: _tileHeight,
              mainAxisSpacing: DashSpace.sm,
              crossAxisSpacing: DashSpace.sm,
            ),
            itemCount: folders.length + files.length,
            itemBuilder: (context, i) => i < folders.length
                ? _FolderTile(
                    folder: folders[i],
                    onTap: () => notifier.openFolder(folders[i].id),
                  )
                : _FileTile(
                    file: files[i - folders.length],
                    printerModel: printerModel,
                  ),
          ),
        ),
      ],
    );
  }
}

/// The frame of every tile: the app's sub-card, with a thumbnail slot.
class _TileFrame extends StatelessWidget {
  const _TileFrame({
    required this.id,
    required this.onTap,
    required this.leading,
    required this.children,
    this.dimmed = false,
  });

  final String id;
  final VoidCallback? onTap;
  final Widget leading;
  final List<Widget> children;

  /// A file that cannot be printed here is quieter, and still opens: its
  /// dialog says why.
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final radius = BorderRadius.circular(DashSpace.md);
    return Opacity(
      opacity: dimmed ? 0.62 : 1,
      child: Material(
        color: t.subCard,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: t.subCardBorder),
        ),
        child: logTag(
          id,
          InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(DashSpace.sm),
              child: Row(
                children: [
                  leading,
                  const SizedBox(width: DashSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: children,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FolderTile extends StatelessWidget {
  const _FolderTile({required this.folder, required this.onTap});

  final LibraryFolder folder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    return _TileFrame(
      id: 'controller.files.folder',
      onTap: onTap,
      leading: Container(
        width: _thumbSize,
        height: _thumbSize,
        decoration: BoxDecoration(
          color: t.warning.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(DashSpace.md),
        ),
        child: Icon(
          Icons.folder_rounded,
          size: DashSpace.xxl,
          color: t.warningInk,
        ),
      ),
      children: [
        Text(
          folder.name,
          style: t.titleSm,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: DashSpace.xs),
        Text(l10n.fmFolderItems(folder.fileCount), style: t.monoLabel),
      ],
    );
  }
}

class _FileTile extends StatelessWidget {
  const _FileTile({required this.file, required this.printerModel});

  final LibraryFile file;
  final String? printerModel;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final printable = file.isPrintable;
    final compatible = isGcodeCompatible(file.slicedForModel, printerModel);
    final meta = printable
        ? [
            if (file.printTimeSeconds case final s?) formatSeconds(l10n, s),
            if (file.filamentUsedGrams case final g?) fmtGrams(g),
          ]
        : [file.fileType.toUpperCase()];
    return _TileFrame(
      id: 'controller.files.file',
      onTap: null,
      dimmed: !printable || !compatible,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(DashSpace.md),
        child: LibraryThumbnail(
          fileId: file.id,
          hasThumbnail: file.thumbnailPath != null,
          size: _thumbSize,
        ),
      ),
      children: [
        Text(
          file.displayName,
          style: t.titleSm,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: DashSpace.xs),
        Row(
          children: [
            Flexible(
              child: Text(
                (meta.isEmpty ? [formatBytes(file.fileSize)] : meta).join(
                  ' · ',
                ),
                style: t.monoLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (!printable) ...[
              const SizedBox(width: DashSpace.sm),
              Flexible(
                child: _Chip(label: l10n.controllerFileNotSliced, warn: true),
              ),
            ] else if (file.slicedForModel case final model?) ...[
              const SizedBox(width: DashSpace.sm),
              Flexible(
                child: _Chip(label: model, warn: !compatible),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// The model a file was sliced for, in the colour that says whether this
/// printer can take it.
class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.warn});

  final String label;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final ink = warn ? t.warningInk : t.accentInk;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: DashSpace.sm),
      decoration: BoxDecoration(
        color: ink.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(DashSpace.sm),
        border: Border.all(color: ink.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (warn) ...[
            Icon(Icons.warning_amber_rounded, size: DashSpace.md, color: ink),
            const SizedBox(width: DashSpace.xs),
          ],
          Flexible(
            child: Text(
              label,
              style: t.monoLabel.copyWith(color: ink),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// A listing that could not be had: the server refused it, or was not there.
class _Failure extends ConsumerWidget {
  const _Failure({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final refused =
        error is AppApiException &&
        (error as AppApiException).code == AppErrorCode.forbidden;
    return _Message(
      icon: refused ? Icons.lock_outline_rounded : Icons.cloud_off_rounded,
      text: refused
          ? (error as AppApiException).localized(l10n)
          : l10n.connectFailed,
      // Nothing to retry for a refusal: the account has to change first.
      action: refused
          ? null
          : logTag(
              'controller.files.retry',
              FilledButton(
                style: controllerButtonStyle(
                  DashTokens.of(context),
                  minimumSize: const Size(0, controllerButtonHeight),
                ),
                onPressed: () => ref.invalidate(fileManagerProvider),
                child: Text(l10n.retry),
              ),
            ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: DashSpace.xxl, color: t.textTertiary),
          const SizedBox(height: DashSpace.md),
          Text(text, style: t.bodySoft, textAlign: TextAlign.center),
          if (action != null) ...[
            const SizedBox(height: DashSpace.lg),
            action!,
          ],
        ],
      ),
    );
  }
}
