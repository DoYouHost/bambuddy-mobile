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
