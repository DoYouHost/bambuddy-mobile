import 'json_utils.dart';

/// A single entry (file or directory) on a printer's storage, as returned by
/// `GET /printers/{id}/files`. The backend adds the full [path] to each entry
/// and includes an optional `mtime` (best-effort parse of the FTP listing).
class PrinterFile {
  const PrinterFile({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.size,
    this.modifiedAt,
  });

  final String name;
  final String path;
  final bool isDirectory;

  /// Size in bytes. `0` for directories (the server doesn't report dir size).
  final int size;

  /// Modification time, or `null` when the FTP listing couldn't be parsed.
  final DateTime? modifiedAt;

  factory PrinterFile.fromJson(Map<String, dynamic> json) => PrinterFile(
    name: toStringOrNull(json['name']) ?? '',
    path: toStringOrNull(json['path']) ?? '',
    // Server key is `is_directory`; treat only an explicit true as a dir.
    isDirectory: json['is_directory'] == true,
    size: toInt(json['size']),
    modifiedAt: dateTimeFromJson(json['mtime']),
  );
}

/// One directory listing from `GET /printers/{id}/files`, plus whether the
/// server managed to talk to the printer at all.
///
/// The listing route answers with an empty `files` for both "this folder is
/// empty" and "the FTP listing did not happen", and newer servers tell the two
/// apart with `warnings: ["printer_unavailable"]`. A server that sends no
/// `warnings` says nothing about it, and then an empty listing reads as an
/// empty folder exactly as before.
class PrinterFileListing {
  const PrinterFileListing({
    this.files = const [],
    this.printerUnavailable = false,
  });

  final List<PrinterFile> files;

  /// The printer did not answer, so [files] is empty for lack of an answer
  /// rather than for lack of files.
  final bool printerUnavailable;

  static const String _unavailableWarning = 'printer_unavailable';

  factory PrinterFileListing.fromJson(Map<String, dynamic> json) =>
      PrinterFileListing(
        files: parseJsonList(json['files'], PrinterFile.fromJson),
        printerUnavailable: toStringList(
          json['warnings'],
        ).contains(_unavailableWarning),
      );
}

/// Storage usage from `GET /printers/{id}/storage`. Both fields are nullable —
/// the printer may not report them (offline/unsupported model).
class PrinterStorage {
  const PrinterStorage({this.usedBytes, this.freeBytes});

  final int? usedBytes;
  final int? freeBytes;

  bool get hasData => usedBytes != null || freeBytes != null;

  factory PrinterStorage.fromJson(Map<String, dynamic> json) => PrinterStorage(
    usedBytes: toIntOrNull(json['used_bytes']),
    freeBytes: toIntOrNull(json['free_bytes']),
  );
}
