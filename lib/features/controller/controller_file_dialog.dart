import 'package:app_util/app_util.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/format/datetime_format.dart';
import '../../core/format/duration_format.dart';
import '../../core/models/library_file.dart';
import '../../core/models/current_user.dart';
import '../../core/models/library_folder.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common/api_failure_snack.dart';
import '../archive/archive_providers.dart';
import '../files/file_manager_providers.dart';
import '../files/library_thumbnail.dart';
import '../stats/stats_common.dart';
import 'controller_detail_dialog.dart';
import 'controller_print.dart';
import 'controller_providers.dart';

/// What the dialog closed with: the user asked to print the file. Anything else
/// (closing, a finished delete) closes with null.
enum ControllerFileChoice { print }

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
  return showControllerDetailDialog(
    context,
    (scale) => _FileDialog(scale: scale, printerId: printerId, file: file),
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
    final block = controllerPrintBlock(
      printerKnown: printer != null,
      refused: ref.watch(permissionProvider(Permissions.queueCreate))
          ? null
          : ArchiveReprintBlock.noQueue,
      printable: _file.isPrintable,
      slicedForModel: _file.slicedForModel,
      printerModel: printer?.model,
    );
    final folders = ref.watch(
      fileManagerProvider.select((s) => s.valueOrNull?.allFolders),
    );
    final folder = folders?.where((f) => f.id == _file.folderId).firstOrNull;
    final mayDelete = mayDeleteLibraryFile(_file, folder);
    final formats = DateTimeFormats.of(context);
    final wrongModel = block == ControllerPrintBlock.wrongModel;
    return ControllerDetailDialog(
      scale: widget.scale,
      closeId: 'controller.files.dialog.close',
      busy: _deleting,
      thumbnail: LibraryThumbnail(
        fileId: _file.id,
        hasThumbnail: _file.thumbnailPath != null,
        size: ControllerDetailDialog.thumbSize,
      ),
      title: _file.displayName,
      facts: [
        ControllerFact(Icons.sd_storage_outlined, formatBytes(_file.fileSize)),
        if (_file.slicedForModel case final model?)
          ControllerFact(
            Icons.print_outlined,
            model,
            ink: wrongModel ? t.warningInk : null,
            fill: wrongModel ? t.warning : null,
          ),
        if (_file.printTimeSeconds case final s?)
          ControllerFact(Icons.schedule_rounded, formatSeconds(l10n, s)),
        if (_file.filamentUsedGrams case final g?)
          ControllerFact(Icons.scale_outlined, fmtGrams(g)),
        if (_file.createdAt case final at?)
          ControllerFact(Icons.event_outlined, formats.dateTime(at.toLocal())),
      ],
      reason: block?.reason(l10n, slicedForModel: _file.slicedForModel),
      actions: [
        if (mayDelete)
          ControllerDialogAction(
            id: 'controller.files.dialog.delete',
            icon: Icons.delete_outline_rounded,
            label: l10n.fmDelete,
            tone: t.danger,
            ink: t.dangerInk,
            onPressed: _deleting ? null : _delete,
          ),
        ControllerDialogAction(
          id: 'controller.files.dialog.print',
          icon: Icons.print_rounded,
          label: l10n.fmPrint,
          tone: t.accentGreen,
          ink: t.accentGreenInk,
          onPressed: block == null && !_deleting
              ? () => Navigator.of(context).pop(ControllerFileChoice.print)
              : null,
        ),
      ],
    );
  }
}
