import 'json_utils.dart';

/// What kind of recording a printer-side file is.
enum ArchiveMediaKind {
  /// A timelapse the printer rendered but the server never attached to the
  /// archive — the copy that would otherwise sit on the SD card unnoticed.
  timelapse,

  /// One `/ipcam` clip whose timestamps fall inside the print. A print
  /// normally has several: the camera writes them in chunks.
  ipcam,
}

/// One downloadable recording found for a print
/// (`GET /archives/{id}/printer-media`).
class ArchiveMediaFile {
  const ArchiveMediaFile({
    required this.name,
    required this.path,
    required this.size,
    required this.kind,
  });

  final String name;

  /// Absolute path on the printer, which is also this file's identity in the
  /// selection — two `/ipcam` chunks can share a name across directories.
  final String path;

  /// Size in bytes, `0` when the FTP listing could not be parsed for one.
  final int size;

  final ArchiveMediaKind kind;

  factory ArchiveMediaFile.fromJson(Map<String, dynamic> json) {
    final name = toStringOrNull(json['name']) ?? '';
    return ArchiveMediaFile(
      name: name,
      path: toStringOrNull(json['path']) ?? '',
      size: toInt(json['size']),
      kind: toStringOrNull(json['kind']) == 'timelapse'
          ? ArchiveMediaKind.timelapse
          : ArchiveMediaKind.ipcam,
    );
  }
}

/// Why part of the search came back empty. The server names these rather than
/// failing the request, because the other half of the answer is still worth
/// showing.
enum ArchiveMediaWarning {
  /// The caller may read archives but not list a printer's files, so nothing
  /// on the printer was looked at.
  printerFilesForbidden,

  /// The archive's printer has since been deleted.
  printerMissing,

  /// No timelapse directory answered — an FTPS handshake the printer refuses,
  /// or a model that keeps none.
  timelapseUnavailable,

  /// `/ipcam` did not answer. Ordinary on a printer with the camera's
  /// recording turned off.
  ipcamUnavailable,
}

/// Everything the server found for one print: the copy it already keeps, and
/// whatever is still on the printer.
///
/// The two halves are downloaded by different routes — the attached timelapse
/// through the archive's own single-use token, the printer's files through the
/// printer file-download job — so they stay separate here rather than being
/// flattened into one list.
class ArchivePrinterMedia {
  const ArchivePrinterMedia({
    this.printerId,
    this.localTimelapse,
    this.remoteFiles = const [],
    this.warnings = const {},
  });

  /// The printer the files live on, and the id the download job is started
  /// against. Null for an archive whose printer is gone or was never set.
  final int? printerId;

  /// The timelapse the server keeps for this archive, when it has one.
  final ArchiveMediaFile? localTimelapse;

  /// Recordings still on the printer's own storage.
  final List<ArchiveMediaFile> remoteFiles;

  final Set<ArchiveMediaWarning> warnings;

  bool get isEmpty => localTimelapse == null && remoteFiles.isEmpty;

  static const _warningNames = {
    'printer_files_forbidden': ArchiveMediaWarning.printerFilesForbidden,
    'printer_missing': ArchiveMediaWarning.printerMissing,
    'timelapse_unavailable': ArchiveMediaWarning.timelapseUnavailable,
    'ipcam_unavailable': ArchiveMediaWarning.ipcamUnavailable,
  };

  factory ArchivePrinterMedia.fromJson(Map<String, dynamic> json) {
    final local = json['local_timelapse'];
    return ArchivePrinterMedia(
      printerId: toIntOrNull(json['printer_id']),
      // The local entry carries only a name and a size; it is downloaded by
      // archive id, so it needs no path and the server sends none.
      localTimelapse: local is Map<String, dynamic>
          ? ArchiveMediaFile(
              name: toStringOrNull(local['name']) ?? '',
              path: '',
              size: toInt(local['size']),
              kind: ArchiveMediaKind.timelapse,
            )
          : null,
      remoteFiles: parseJsonList(json['remote_files'], ArchiveMediaFile.fromJson)
          .where((f) => f.path.isNotEmpty)
          .toList(),
      // An unknown warning is dropped rather than surfaced: a newer server may
      // name a case this build has no sentence for, and a raw wire string is
      // not something to put in front of the user.
      warnings: {
        for (final name in toStringList(json['warnings'])) ?_warningNames[name],
      },
    );
  }
}
