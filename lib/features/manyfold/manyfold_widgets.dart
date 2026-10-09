import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/models/manyfold.dart';
import '../../core/theme/dash_theme.dart';
import '../../data/manyfold_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import '../common/api_failure_snack.dart';
import '../common/dash_input.dart';
import 'manyfold_providers.dart';

/// The web's `errorText`: our own sentence for a code Manyfold's failures
/// carry, the usual one for anything else.
String manyfoldErrorText(Object error, AppLocalizations l10n) =>
    switch (error) {
      ManyfoldFailure(:final code) => switch (code) {
        'manyfold_not_configured' => l10n.mfErrNotConfigured,
        'manyfold_credentials' => l10n.mfErrCredentials,
        'manyfold_scope' => l10n.mfErrScope,
        'manyfold_rate_limited' => l10n.mfErrRateLimited,
        'manyfold_unreachable' => l10n.mfErrUnreachable,
        'manyfold_forbidden' => l10n.mfErrForbidden,
        'manyfold_not_found' => l10n.mfErrNotFound,
        'manyfold_too_large' => l10n.mfErrTooLarge,
        'manyfold_not_importable' => l10n.mfErrNotImportable,
        'manyfold_bad_url' => l10n.mfErrBadUrl,
        'manyfold_secret_required' => l10n.mfErrSecretRequired,
        _ => l10n.mfErrFailed,
      },
      AppApiException e => e.localized(l10n),
      _ => l10n.mfErrFailed,
    };

/// Records a failed action and tells the user, for both kinds of failure a
/// Manyfold call raises. Pass `mounted ? messenger : null`, as to
/// [showApiFailure].
void showManyfoldFailure(
  ScaffoldMessengerState? messenger,
  Object error,
  AppLocalizations l10n, {
  required String action,
}) {
  final cause = switch (error) {
    ManyfoldFailure(:final cause) => cause,
    AppApiException e => e,
    _ => null,
  };
  if (cause != null) {
    recordActionFailure(cause, action: action, shown: messenger != null);
  }
  messenger?.snack(manyfoldErrorText(error, l10n));
}

typedef ManyfoldImportItem = ({String modelId, String fileId, String name});

/// The web's `useManyfoldBulkImport`: one file after another, not in
/// parallel, to go easy on Manyfold and the disk. A file that fails does not
/// stop the rest; one summary at the end says what happened.
Future<void> importManyfoldFiles(
  ManyfoldRepository repo,
  List<ManyfoldImportItem> items, {
  required int? folderId,
  required ScaffoldMessengerState messenger,
  required AppLocalizations l10n,
  required void Function(int current, int total) onProgress,
  required bool Function() mounted,

  /// The control that started it, for the `action_failed` records.
  required String action,
}) async {
  if (items.isEmpty) {
    messenger.snack(l10n.mfBulkNothing);
    return;
  }
  var imported = 0;
  var existing = 0;
  final failed = <String>[];
  Object? firstError;
  for (var i = 0; i < items.length; i++) {
    onProgress(i + 1, items.length);
    final item = items[i];
    try {
      final result = await repo.import(
        modelId: item.modelId,
        fileId: item.fileId,
        folderId: folderId,
      );
      result.wasExisting ? existing++ : imported++;
    } on Object catch (e) {
      if (e is! ManyfoldFailure && e is! AppApiException) rethrow;
      failed.add(item.name);
      firstError ??= e;
      if (e case ManyfoldFailure(:final cause) || final AppApiException cause) {
        recordActionFailure(cause, action: action, shown: mounted());
      }
    }
  }
  if (!mounted()) return;
  messenger.snack(l10n.mfBulkDone(imported, existing, failed.length));
  if (failed.isNotEmpty) {
    messenger.snack(
      l10n.mfBulkFailed(
        manyfoldListNames(failed),
        manyfoldErrorText(firstError!, l10n),
      ),
    );
  }
}

/// The first few names, then how many more.
String manyfoldListNames(List<String> names) => names.length > 3
    ? '${names.take(3).join(', ')} +${names.length - 3}'
    : names.join(', ');

/// A model's preview from Manyfold, or a placeholder when it has none.
class ManyfoldPreview extends ConsumerWidget {
  const ManyfoldPreview({super.key, required this.modelId, this.size});

  final String modelId;

  /// Square side; `null` fills the width it is given.
  final double? size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DashTokens.of(context);
    final bytes = ref.watch(manyfoldPreviewProvider(modelId));
    final image = bytes.valueOrNull;
    final Widget child = image != null
        ? Image.memory(image, fit: BoxFit.contain, gaplessPlayback: true)
        : Center(
            child: bytes.isLoading
                ? const DashSpinner()
                : Icon(
                    Icons.view_in_ar_outlined,
                    size: 36,
                    color: t.textTertiary,
                  ),
          );
    return Container(
      width: size,
      height: size,
      color: t.subCard,
      child: size == null ? AspectRatio(aspectRatio: 1, child: child) : child,
    );
  }
}

/// "Import to": the "Manyfold" folder by default, or any folder the user may
/// write to. The web's `ImportFolderSelect`.
class ManyfoldFolderCombo extends ConsumerWidget {
  const ManyfoldFolderCombo({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final int? value;
  final ValueChanged<int?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final folders =
        ref.watch(manyfoldImportFoldersProvider).valueOrNull ?? const [];
    return dashCombo<int?>(
      context,
      id: 'manyfold.import_folder',
      label: Text(l10n.mfImportTo),
      enabled: enabled,
      initialSelection: value,
      onSelected: onChanged,
      entries: [
        DropdownMenuEntry(
          value: null,
          label: l10n.mfFolderAuto,
          labelWidget: Text(l10n.mfFolderAuto).tagged('manyfold.folder_auto'),
        ),
        for (final (folder, depth) in folders)
          DropdownMenuEntry(
            value: folder.id,
            // Listed for the tree's shape; only folders the user may write to
            // take imports (#3201).
            enabled: folder.canWrite,
            label: '${'— ' * depth}${folder.name}',
            labelWidget: Text(
              '${'— ' * depth}${folder.name}',
            ).tagged('manyfold.folder_option'),
          ),
      ],
    );
  }
}
