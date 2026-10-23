import '../../core/models/archive.dart';
import '../../core/models/library_file.dart';
import '../../core/models/queue_item.dart';

/// The queue draft a reprint of [archive] starts from. The archive's own
/// printer is a starting point, not a decision — the form lists every printer
/// and the user can switch before anything is created.
QueueItem archiveQueueDraft(Archive archive, {bool manualStart = false}) =>
    QueueItem.draft(
      archiveId: archive.id,
      name: archive.displayName,
      thumbnail: archive.thumbnailPath,
      printerId: archive.printerId,
      filamentType: archive.filamentType,
      filamentColor: archive.filamentColor,
      slicedForModel: archive.slicedForModel,
      // The plate this print ran on, so a reprint runs the same one. Null on
      // a single-plate file and on servers that do not report it, which is
      // what the form and the server both read as plate 1.
      plateId: archive.plateId,
      manualStart: manualStart,
      // Sticky on the server: a reprint of an archive that asked asks again.
      confirmOutcome: archive.confirmRequested,
      printTimeSeconds: archive.printTimeSeconds,
      filamentUsedGrams: archive.filamentUsedGrams,
    );

/// The queue draft printing a library [file] starts from, wherever it is
/// printed from: the file manager, a project, the controller.
QueueItem libraryFileQueueDraft(LibraryFile file) => QueueItem.draft(
  libraryFileId: file.id,
  name: file.displayName,
  thumbnail: file.thumbnailPath,
  slicedForModel: file.slicedForModel,
  printTimeSeconds: file.printTimeSeconds,
  filamentUsedGrams: file.filamentUsedGrams,
);
