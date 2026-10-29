import 'scale_to_fit.dart';
import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:app_util/app_util.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/format/duration_format.dart';
import '../../core/models/library_file.dart';
import '../../core/models/library_folder.dart';
import '../../core/printers/gcode_compat.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common/api_failure_snack.dart';
import '../common/device_files.dart';
import '../files/file_manager_providers.dart';
import '../queue/queue_drafts.dart';
import '../files/library_thumbnail.dart';
import '../stats/stats_common.dart';
import 'controller_controls.dart';
import 'controller_file_dialog.dart';
import 'controller_list_parts.dart';
import 'controller_print.dart';
import 'controller_providers.dart';

/// The Files tab: the server's file library, scoped to the controller's printer
/// ([docs/single-printer-controller.md]). The library is the only source a print
/// can start from — the server cannot start one from the printer's own storage.
///
/// Reads [fileManagerProvider], which the controller keeps alive while it is
/// open so the folder and the sort survive a visit to another tab.
class ControllerFiles extends ConsumerStatefulWidget {
  const ControllerFiles({super.key, required this.printerId});

  final int printerId;

  @override
  ConsumerState<ControllerFiles> createState() => _ControllerFilesState();
}

class _ControllerFilesState extends ConsumerState<ControllerFiles> {
  /// A file is being picked or sent. Set before the picker opens, so a second
  /// tap cannot start a second upload.
  bool _uploading = false;

  /// Null while the size is unknown, and until the first chunk is sent.
  double? _progress;

  Future<void> _upload(FileManagerState s) async {
    if (_uploading) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context);
    setState(() => _uploading = true);
    final picked = await pickFileFromDevice();
    if (!mounted) return;
    final file = picked.file;
    if (file == null) {
      setState(() => _uploading = false);
      if (picked.outcome == DeviceFileOutcome.failed) {
        messenger.snack(l10n.fmUploadFailed);
      }
      return;
    }
    try {
      await container
          .read(libraryRepositoryProvider)
          .uploadFile(
            filePath: file.path,
            filename: file.name,
            folderId: s.currentFolderId,
            onProgress: (p) {
              if (mounted) setState(() => _progress = p);
            },
          );
      // Through the container, which outlives this tab: the library is kept
      // by the controller, so a tab left mid-upload still gets its new file.
      // Not once the controller is gone and the library with it.
      if (container.exists(fileManagerProvider)) {
        await container.read(fileManagerProvider.notifier).refresh();
      }
      container.invalidate(libraryStatsProvider);
      if (mounted) messenger.snack(l10n.fmUploaded(file.name));
    } on AppApiException catch (e) {
      // Unmounted, only the record is written: it reached nobody.
      showApiFailure(
        mounted ? messenger : null,
        e,
        l10n,
        action: 'controller.files.upload',
      );
    } finally {
      if (mounted) {
        setState(() {
          _uploading = false;
          _progress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final async = ref.watch(fileManagerProvider);
    // Kept while a refresh is under way, so the grid does not blink out.
    final state = async.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          state: state,
          loading: async.isLoading,
          uploading: _uploading,
          progress: _progress,
          onUpload: state == null ? null : () => _upload(state),
        ),
        const SizedBox(height: DashSpace.md),
        Expanded(
          child: Container(
            decoration: t.cardBox,
            padding: const EdgeInsets.all(DashSpace.sm),
            // The error first: a failed refresh or a failed step into a folder
            // keeps the listing it came from as `value`, and showing that
            // would leave the user looking at the old folder with no word.
            child: switch ((state, async)) {
              (_, AsyncError(:final error)) => ControllerListFailure(
                error: error,
                retryId: 'controller.files.retry',
                onRetry: () => ref.invalidate(fileManagerProvider),
              ),
              (final s?, _) => _Grid(
                state: s,
                printerId: widget.printerId,
                refreshing: async.isLoading,
                // What a tap would act on is about to change.
                locked: async.isLoading || _uploading,
              ),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ),
        ),
      ],
    );
  }
}

/// Up, where the user is, the search, the sort, an upload and a refresh.
class _Header extends ConsumerStatefulWidget {
  const _Header({
    required this.state,
    required this.loading,
    required this.uploading,
    required this.progress,
    required this.onUpload,
  });

  final FileManagerState? state;

  /// A listing is on its way: what the buttons would act on is about to change.
  final bool loading;

  /// A file is being sent: the header answers nothing but the bar.
  final bool uploading;
  final double? progress;
  final VoidCallback? onUpload;

  @override
  ConsumerState<_Header> createState() => _HeaderState();
}

class _HeaderState extends ConsumerState<_Header> {
  final _query = TextEditingController();

  /// The search field is open. It is a field of the header and not a dialog: a
  /// dialog is inset by the keyboard and is left with about 100 dp.
  bool _editing = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _openSearch() {
    _query.text = widget.state?.query ?? '';
    setState(() => _editing = true);
  }

  void _apply(String text) {
    setState(() => _editing = false);
    ref.read(fileManagerProvider.notifier).setQuery(text.trim());
  }

  void _clear() => ref.read(fileManagerProvider.notifier).setQuery('');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final s = widget.state;
    final locked = widget.uploading;
    final notifier = ref.read(fileManagerProvider.notifier);
    final folder = s?.currentFolder;
    // The server refuses a write to either; an external mount is also the
    // host's, not the library's.
    final readOnly =
        folder != null &&
        (folder.isExternal || folder.externalReadonly || !folder.canWrite);
    return Row(
      children: [
        ControllerHeaderButton(
          id: 'controller.files.up',
          tooltip: l10n.pfmUp,
          icon: Icons.arrow_upward_rounded,
          // Not while a step is in flight, which would read the folder it is
          // leaving; and a folder the tree no longer holds still has a way out,
          // to the root.
          onPressed: s?.currentFolderId == null || widget.loading || locked
              ? null
              : () => notifier.openFolder(folder?.parentId),
        ),
        const SizedBox(width: DashSpace.sm),
        Expanded(
          child: _editing
              ? _SearchField(
                  controller: _query,
                  hint: l10n.fmSearchHint,
                  onSubmitted: _apply,
                  onCancel: () => setState(() => _editing = false),
                )
              : _PathCard(
                  state: s,
                  progress: widget.uploading ? widget.progress : null,
                  uploading: widget.uploading,
                  onClearQuery: _clear,
                ),
        ),
        const SizedBox(width: DashSpace.sm),
        ControllerHeaderButton(
          id: 'controller.files.search',
          tooltip: l10n.fmSearchHint,
          icon: Icons.search_rounded,
          onPressed: s == null || locked || _editing ? null : _openSearch,
        ),
        const SizedBox(width: DashSpace.sm),
        ControllerHeaderButton(
          id: 'controller.files.sort',
          tooltip: l10n.fmSortBy,
          icon: Icons.sort_rounded,
          // Six orders on a touch panel: one tap moves to the next, and the
          // label beside the path says which is on.
          onPressed: s == null || locked
              ? null
              : () => notifier.setSort(
                  FileSort.values[(s.sort.index + 1) % FileSort.values.length],
                ),
        ),
        const SizedBox(width: DashSpace.sm),
        ControllerHeaderButton(
          id: 'controller.files.upload',
          // A disabled button has no label of its own, so the tooltip says why.
          tooltip: readOnly ? l10n.controllerFilesReadOnly : l10n.fmUpload,
          icon: Icons.upload_file_rounded,
          onPressed: s == null || widget.loading || locked || readOnly
              ? null
              : widget.onUpload,
        ),
        const SizedBox(width: DashSpace.sm),
        ControllerHeaderButton(
          id: 'controller.files.refresh',
          tooltip: l10n.pfmRefreshTooltip,
          icon: Icons.refresh_rounded,
          onPressed: s == null || widget.loading || locked
              ? null
              : notifier.refresh,
        ),
      ],
    );
  }
}

/// Where the user is, the order, the search that is applied, and the bar of an
/// upload on its way.
class _PathCard extends StatelessWidget {
  const _PathCard({
    required this.state,
    required this.progress,
    required this.uploading,
    required this.onClearQuery,
  });

  final FileManagerState? state;
  final double? progress;
  final bool uploading;
  final VoidCallback onClearQuery;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final s = state;
    final path = [
      l10n.fmRoot,
      for (final f in s?.breadcrumb ?? const []) f.name,
    ];
    return ControllerHeaderCard(
      title: path.join('  /  '),
      extras: [
        if (s != null && s.isSearching)
          Flexible(
            child: _QueryChip(query: s.query.trim(), onTap: onClearQuery),
          ),
      ],
      fact: s == null ? null : _sortLabel(l10n, s.sort),
      busy: uploading,
      progress: progress,
    );
  }
}

/// The applied search, dismissed by a tap anywhere on it.
class _QueryChip extends StatelessWidget {
  const _QueryChip({required this.query, required this.onTap});

  final String query;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final radius = BorderRadius.circular(DashSpace.md);
    return Tooltip(
      message: MaterialLocalizations.of(context).clearButtonTooltip,
      child: logTag(
        'controller.files.search_chip',
        InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(
              minHeight: kMinInteractiveDimension,
            ),
            padding: const EdgeInsets.symmetric(horizontal: DashSpace.md),
            decoration: BoxDecoration(
              color: t.accentInk.withValues(alpha: 0.12),
              borderRadius: radius,
              border: Border.all(color: t.accentInk.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    query,
                    style: t.monoLabel.copyWith(color: t.accentInk),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: DashSpace.xs),
                Icon(
                  Icons.close_rounded,
                  size: controllerIconSize(context, DashSpace.lg),
                  color: t.accentInk,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The search field that takes the path card's place: applied on the keyboard's
/// search action, not on every key, because the first search fetches the whole
/// library.
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.hint,
    required this.onSubmitted,
    required this.onCancel,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Container(
      height: controllerButtonHeight,
      padding: const EdgeInsets.only(left: DashSpace.lg),
      decoration: t.cardBox,
      child: Row(
        children: [
          Expanded(
            child: logTag(
              'controller.files.search_field',
              TextField(
                controller: controller,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onSubmitted: onSubmitted,
                style: t.bodyStrong,
                decoration: InputDecoration(
                  hintText: hint,
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
          ),
          logTag(
            'controller.files.search_cancel',
            IconButton(
              tooltip: MaterialLocalizations.of(context).cancelButtonLabel,
              color: t.textPrimary,
              icon: const Icon(Icons.close_rounded),
              onPressed: onCancel,
            ),
          ),
        ],
      ),
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

/// Folders first, then files; what the library screen would list, in the
/// controller's tiles.
class _Grid extends ConsumerWidget {
  const _Grid({
    required this.state,
    required this.printerId,
    required this.refreshing,
    required this.locked,
  });

  final FileManagerState state;
  final int printerId;
  final bool refreshing;

  /// Nothing opens: a listing is on its way, or a file is being sent.
  final bool locked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final notifier = ref.read(fileManagerProvider.notifier);
    final model = ref.watch(
      controllerPrinterProvider(printerId).select((p) => p.item?.printer.model),
    );
    // A search or a tag filter spans the whole library, so the folders of the
    // directory the user stands in would be noise beside its results.
    final folders = state.isSearching || state.isTagFiltering
        ? const <LibraryFolder>[]
        : state.subfolders;
    final files = state.visibleFiles;
    // The library-wide fetch of a search or a tag filter: until it answers the
    // list is empty, which is not "no matches".
    if (state.searching && files.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (folders.isEmpty && files.isEmpty) {
      final failed =
          state.fetchFailed && (state.isSearching || state.isTagFiltering);
      return ControllerListMessage(
        icon: failed ? Icons.cloud_off_rounded : Icons.folder_open_outlined,
        text: failed
            ? l10n.connectFailed
            : state.isSearching ||
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
            gridDelegate: controllerTileGrid(context),
            itemCount: folders.length + files.length,
            itemBuilder: (context, i) => i < folders.length
                ? _FolderTile(
                    folder: folders[i],
                    onTap: locked
                        ? null
                        : () => notifier.openFolder(folders[i].id),
                  )
                : _FileTile(
                    file: files[i - folders.length],
                    printerModel: model,
                    onTap: locked
                        ? null
                        : () => _openFile(
                            context,
                            ref,
                            files[i - folders.length],
                          ),
                  ),
          ),
        ),
      ],
    );
  }

  /// The file's dialog, then the print screen when Print was chosen. The
  /// printer is read after the dialog: the roster may have lost it meanwhile.
  Future<void> _openFile(
    BuildContext context,
    WidgetRef ref,
    LibraryFile file,
  ) async {
    final choice = await showControllerFileDialog(
      context,
      printerId: printerId,
      file: file,
    );
    if (choice != ControllerFileChoice.print || !context.mounted) return;
    final printer = ref
        .read(controllerPrinterProvider(printerId))
        .item
        ?.printer;
    if (printer == null) return;
    await openControllerPrint(
      context,
      printer: printer,
      draft: libraryFileQueueDraft(file),
    );
  }
}

class _FolderTile extends StatelessWidget {
  const _FolderTile({required this.folder, required this.onTap});

  final LibraryFolder folder;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    return ControllerTileFrame(
      id: 'controller.files.folder',
      onTap: onTap,
      leading: Container(
        width: controllerThumbSize,
        height: controllerThumbSize,
        decoration: BoxDecoration(
          color: t.warning.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(DashSpace.md),
        ),
        child: Icon(
          Icons.folder_rounded,
          size: controllerIconSize(context, DashSpace.xxl),
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
  const _FileTile({
    required this.file,
    required this.printerModel,
    required this.onTap,
  });

  final LibraryFile file;
  final String? printerModel;
  final VoidCallback? onTap;

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
    return ControllerTileFrame(
      id: 'controller.files.file',
      onTap: onTap,
      dimmed: !printable || !compatible,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(DashSpace.md),
        child: LibraryThumbnail(
          fileId: file.id,
          hasThumbnail: file.thumbnailPath != null,
          size: controllerThumbSize,
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
                child: ControllerChip(
                  label: l10n.controllerFileNotSliced,
                  ink: t.warningInk,
                  icon: Icons.warning_amber_rounded,
                ),
              ),
            ] else if (file.slicedForModel case final model?) ...[
              const SizedBox(width: DashSpace.sm),
              Flexible(
                child: ControllerChip(
                  label: model,
                  ink: compatible ? t.accentInk : t.warningInk,
                  icon: compatible ? null : Icons.warning_amber_rounded,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
