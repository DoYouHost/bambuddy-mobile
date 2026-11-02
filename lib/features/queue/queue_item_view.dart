import 'package:material_ui/material_ui.dart';

import '../../core/models/queue_item.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../common/print_thumbnail.dart';
import '../files/library_thumbnail.dart';

/// A queued job's picture: the library file's own thumbnail for a job queued
/// from the library, the archive's otherwise. The caller clips it.
class QueueThumbnail extends StatelessWidget {
  const QueueThumbnail({super.key, required this.item, required this.size});

  final QueueItem item;
  final double size;

  @override
  Widget build(BuildContext context) =>
      item.archiveId == null && item.libraryFileId != null
      ? LibraryThumbnail(
          fileId: item.libraryFileId!,
          hasThumbnail: item.libraryFileThumbnail != null,
          size: size,
        )
      : PrintThumbnail(archiveId: item.archiveId, size: size);
}

/// What a job's status chip says, and in which colour. An unknown status is
/// shown as it came, in the quiet colour.
(String, Color) queueStatusLabel(
  AppLocalizations l10n,
  DashTokens t,
  QueueItem item,
) => switch (item.statusKind) {
  QueueItemStatusKind.printing => (l10n.queueStatusPrinting, t.accentGreenInk),
  QueueItemStatusKind.paused => (l10n.queueStatusPaused, t.accentOrangeInk),
  QueueItemStatusKind.scheduled => (l10n.queueStatusScheduled, t.accentBlue),
  QueueItemStatusKind.pending => (l10n.queueStatusPending, t.textTertiary),
  _ => (item.status, t.textTertiary),
};

/// The web's Staged badge on a job that waits for a manual start: it says who
/// starts it to a user held for review (#1620).
String queueStagedLabel(
  AppLocalizations l10n, {
  required bool awaitingReview,
}) => awaitingReview ? l10n.queueBadgeAwaitingReview : l10n.queueBadgeStaged;

/// Where a job with no printer on it will run. A cross-model job (server #671)
/// names its candidates — the user chose that set — and a model-based one its
/// model. Whether a printer's name comes first is the caller's to decide.
String queueTargetLabel(AppLocalizations l10n, QueueItem item) {
  if (item.isCrossModel) {
    return l10n.queueAnyOfModels(
      [for (final v in item.variants) v.targetModel].join(', '),
    );
  }
  final model = item.targetModel;
  return model != null
      ? l10n.queueEditAnyModel(model)
      : l10n.printLogAnyPrinter;
}
