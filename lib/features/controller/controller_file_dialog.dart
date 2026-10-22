import 'dart:math' as math;

import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:app_util/app_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/format/datetime_format.dart';
import '../../core/format/duration_format.dart';
import '../../core/models/library_file.dart';
import '../../core/models/library_folder.dart';
import '../../core/printers/gcode_compat.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common/api_failure_snack.dart';
import '../files/file_manager_providers.dart';
import '../files/library_thumbnail.dart';
import '../stats/stats_common.dart';
import 'controller_controls.dart';
import 'controller_providers.dart';
import 'scale_to_fit.dart';

/// What the dialog closed with: the user asked to print the file. Anything else
/// (closing, a finished delete) closes with null.
enum ControllerFileChoice { print }

/// Why a file cannot be printed on [printerModel], or null when it can. A
/// printer missing from the roster is [printerModel] == null and `gone`.
///
/// Mirrors the tile's own dimming, so a quiet tile and a disabled button agree.
enum FilePrintBlock { printerGone, notSliced, wrongModel }

FilePrintBlock? filePrintBlock(
  LibraryFile file, {
  required bool printerKnown,
  required String? printerModel,
}) {
  if (!printerKnown) return FilePrintBlock.printerGone;
  if (!file.isPrintable) return FilePrintBlock.notSliced;
  if (!isGcodeCompatible(file.slicedForModel, printerModel)) {
    return FilePrintBlock.wrongModel;
  }
  return null;
}

/// A file may be deleted from the controller unless it lives on a mount the host
/// owns, or in a folder the account may not write to (#3201).
bool mayDeleteLibraryFile(LibraryFile file, LibraryFolder? folder) =>
    !file.isExternal &&
    !(folder != null &&
        (folder.isExternal || folder.externalReadonly || !folder.canWrite));

/// Opens the dialog of one library file, scaled like the controller body.
Future<ControllerFileChoice?> showControllerFileDialog(
  BuildContext context, {
  required int printerId,
  required LibraryFile file,
}) {
  // Read here, under the body: the dialog's route is not.
  final scale = ControllerScale.of(context);
  return showDialog<ControllerFileChoice>(
    context: context,
    builder: (_) => _FileDialog(scale: scale, printerId: printerId, file: file),
  );
}

class _FileDialog extends ConsumerStatefulWidget {
  const _FileDialog({
    required this.scale,
    required this.printerId,
    required this.file,
  });

  final double scale;
  final int printerId;
  final LibraryFile file;

  @override
  ConsumerState<_FileDialog> createState() => _FileDialogState();
}

class _FileDialogState extends ConsumerState<_FileDialog> {
  /// The size the content is laid out for, before the whole is scaled to the
  /// room the screen gives it.
  static const _width = 560.0;
  static const _height = 260.0;
  static const _thumb = 148.0;

  /// A delete is under way: nothing else on the dialog answers meanwhile.
  bool _deleting = false;

  LibraryFile get _file => widget.file;

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await confirmDialog(
      context,
      id: 'controller.files.delete_confirm',
      title: l10n.fmDeleteFile,
      message: l10n.fmDeleteFileConfirm(_file.displayName),
      confirmLabel: l10n.fmDelete,
    );
    if (!ok || !mounted) return;
    setState(() => _deleting = true);
    final nav = Navigator.of(context);
    // The listing is the screen's, not the dialog's: it is refreshed through the
    // container, which outlives this dialog if it is closed mid-request.
    final container = ProviderScope.containerOf(context);
    try {
      await container.read(libraryRepositoryProvider).deleteFile(_file.id);
      container.invalidate(libraryStatsProvider);
      await container.read(fileManagerProvider.notifier).refresh();
      messenger.snack(l10n.fmDeleted);
      if (mounted) nav.pop();
    } on AppApiException catch (e) {
      if (mounted) setState(() => _deleting = false);
      showApiFailure(
        mounted ? messenger : null,
        e,
        l10n,
        action: 'controller.files.dialog.delete',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final printer = ref.watch(
      controllerPrinterProvider(
        widget.printerId,
      ).select((p) => p.item?.printer),
    );
    final block = filePrintBlock(
      _file,
      printerKnown: printer != null,
      printerModel: printer?.model,
    );
    final folders = ref.watch(
      fileManagerProvider.select((s) => s.valueOrNull?.allFolders),
    );
    final folder = folders?.where((f) => f.id == _file.folderId).firstOrNull;
    final mayDelete = mayDeleteLibraryFile(_file, folder);
    final formats = DateTimeFormats.of(context);
    final facts = [
      formatBytes(_file.fileSize),
      ?_file.slicedForModel,
      if (_file.printTimeSeconds case final s?) formatSeconds(l10n, s),
      if (_file.filamentUsedGrams case final g?) fmtGrams(g),
      if (_file.createdAt case final at?) formats.dateTime(at.toLocal()),
    ];
    return Dialog(
      insetPadding: const EdgeInsets.all(DashSpace.md),
      child: LayoutBuilder(
        builder: (context, box) => SizedBox(
          width: math.min(_width * widget.scale, box.maxWidth),
          height: math.min(_height * widget.scale, box.maxHeight),
          child: ScaleToFit(
            minSize: const Size(_width, _height),
            child: Padding(
              padding: const EdgeInsets.all(DashSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(DashSpace.md),
                          child: LibraryThumbnail(
                            fileId: _file.id,
                            hasThumbnail: _file.thumbnailPath != null,
                            size: _thumb,
                          ),
                        ),
                        const SizedBox(width: DashSpace.lg),
                        Expanded(child: _details(t, facts)),
                      ],
                    ),
                  ),
                  if (block != null) ...[
                    Text(
                      switch (block) {
                        FilePrintBlock.printerGone =>
                          l10n.controllerPrinterGone,
                        FilePrintBlock.notSliced =>
                          l10n.controllerFileReasonNotSliced,
                        FilePrintBlock.wrongModel =>
                          l10n.controllerFileReasonModel(
                            _file.slicedForModel ?? '',
                          ),
                      },
                      style: t.bodySoft.copyWith(color: t.warningInk),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: DashSpace.sm),
                  ],
                  _buttons(
                    t,
                    l10n,
                    canPrint: block == null,
                    mayDelete: mayDelete,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _details(DashTokens t, List<String> facts) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                _file.displayName,
                style: t.titleMd,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            logTag(
              'controller.files.dialog.close',
              IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                color: t.textPrimary,
                icon: const Icon(Icons.close_rounded),
                onPressed: _deleting ? null : () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
        const SizedBox(height: DashSpace.sm),
        Wrap(
          spacing: DashSpace.md,
          runSpacing: DashSpace.xs,
          children: [for (final fact in facts) Text(fact, style: t.monoLabel)],
        ),
      ],
    );
  }

  Widget _buttons(
    DashTokens t,
    AppLocalizations l10n, {
    required bool canPrint,
    required bool mayDelete,
  }) {
    final style = controllerButtonStyle(
      t,
      minimumSize: const Size(0, controllerButtonHeight),
    );
    return Row(
      children: [
        if (mayDelete) ...[
          Expanded(
            child: logTag(
              'controller.files.dialog.delete',
              FilledButton.icon(
                style: controllerButtonStyle(
                  t,
                  minimumSize: const Size(0, controllerButtonHeight),
                  tone: t.danger,
                  ink: t.dangerInk,
                ),
                onPressed: _deleting ? null : _delete,
                icon: const Icon(Icons.delete_outline_rounded),
                label: Text(l10n.fmDelete),
              ),
            ),
          ),
          const SizedBox(width: DashSpace.md),
        ],
        Expanded(
          child: logTag(
            'controller.files.dialog.print',
            FilledButton.icon(
              style: canPrint
                  ? controllerButtonStyle(
                      t,
                      minimumSize: const Size(0, controllerButtonHeight),
                      tone: t.accentGreen,
                      ink: t.accentGreenInk,
                    )
                  : style,
              onPressed: canPrint && !_deleting
                  ? () => Navigator.of(context).pop(ControllerFileChoice.print)
                  : null,
              icon: const Icon(Icons.print_rounded),
              label: Text(l10n.fmPrint),
            ),
          ),
        ),
      ],
    );
  }
}
