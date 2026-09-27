import 'dart:io';

import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'device_files.dart';

/// Getting something big out of the app: pull it down into a cache file, then
/// let the user say where it goes.
///
/// The save dialog is `flutter_file_dialog`'s because it takes a *path* and
/// streams the copy on the platform side; `file_picker`'s `saveFile` takes only
/// bytes on Android, which put a whole print through the phone's RAM.
///
/// **Whether the caller may drop the cache copy itself differs by hand-off.**
/// [saveDownloadedFile] has finished copying when it returns, so a caller that
/// downloads under the file's own name should delete it or leave one duplicate
/// per name behind. [shareDownloadedFile] has *not*: the sheet closes before
/// the receiving app reads the URI, so deleting there is how a share arrives
/// empty.

/// Streams a download into the cache directory under [scratchName], then
/// renames it to whatever [name] makes of the served `Content-Type`.
///
/// [download] is handed the path to write to and returns that content type. The
/// two-step rename is for routes that only say what the file is *as* they serve
/// it — one timelapse URL answers MP4, AVI or MKV — and a file under the wrong
/// extension is one nothing will open. A failed download takes its part-file
/// with it: nothing here resumes one, and a scratch named after the archive
/// would otherwise keep a full-size partial per interrupted video.
Future<File> downloadToCacheFile({
  required String scratchName,
  required Future<String?> Function(String savePath) download,
  required String Function(String? contentType) name,
}) async {
  final dir = await getTemporaryDirectory();
  final scratch = '${dir.path}/$scratchName';
  final String? contentType;
  try {
    contentType = await download(scratch);
  } on Object {
    await discardCacheCopy(File(scratch));
    rethrow;
  }
  final target = File('${dir.path}/${name(contentType)}');
  return File(scratch).rename(target.path);
}

/// Drops a cache copy that has served its purpose. Missing is not an error but
/// the wanted state — the system may reclaim the cache at any point.
Future<void> discardCacheCopy(File file) async {
  try {
    await file.delete();
  } on FileSystemException {
    // Already gone.
  }
}

/// Hands [file] to the system share sheet. [mimeType] decides which apps the
/// sheet offers; null lets the platform guess from the extension.
Future<void> shareDownloadedFile(File file, {String? mimeType}) => SharePlus
    .instance
    .share(ShareParams(files: [XFile(file.path, mimeType: mimeType)]));

/// Asks the user where to keep [file] and copies it there — "Save as…", not the
/// share sheet, which on a phone without Files by Google cannot save to local
/// storage at all. [fileName] is only the suggestion.
///
/// Returns once the copy is done, so [file] is the caller's to delete straight
/// after — on a cancel and a failure too.
Future<SavedFileResult> saveDownloadedFile(
  File file, {
  required String fileName,
  String? mimeType,
}) async {
  try {
    final path = await FlutterFileDialog.saveFile(
      params: SaveFileDialogParams(
        sourceFilePath: file.path,
        fileName: fileName,
        mimeTypesFilter: mimeType == null ? null : [mimeType],
      ),
    );
    return path == null
        ? (outcome: DeviceFileOutcome.cancelled, path: null)
        : (outcome: DeviceFileOutcome.done, path: path);
  } on Exception {
    // The plugin throws on a failed copy — no room on the target, a revoked
    // permission, a URI the system would not open.
    return (outcome: DeviceFileOutcome.failed, path: null);
  }
}

/// A print's name reduced to something a filesystem and a share target will
/// both accept. A leading dot would make a hidden file, a trailing one collides
/// with the suffix the caller appends, and `..` disappears with the separators,
/// so a name cannot walk out of the directory it is saved into.
///
/// [fallback] has no default: `timelapse` and `archive` are each the wrong word
/// in the other's place.
///
/// **Letters and digits of any script survive.** `\p{L}\p{N}` needs
/// `unicode: true` to mean anything — without the flag Dart reads `\p` as a
/// literal `p`, and `\w` is ASCII, which is what reduced `Łódź` to `d`.
String safeFileStem(String name, {required String fallback}) {
  final safe = name
      .replaceAll(RegExp(r'[^\p{L}\p{N}\s._-]', unicode: true), '')
      .trim()
      .replaceAll(RegExp(r'\s+'), '_')
      .replaceAll(RegExp(r'^[._]+|[._]+$'), '');
  return safe.isEmpty ? fallback : safe;
}

/// Media types for the files a printer keeps. Anything else is left to the
/// platform to guess — better than an octet-stream some share targets refuse.
const _printerFileTypes = {
  '3mf': 'model/3mf',
  'gcode': 'text/x.gcode',
  'zip': 'application/zip',
  'json': 'application/json',
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'mp4': 'video/mp4',
  'avi': 'video/x-msvideo',
  'mkv': 'video/x-matroska',
};

/// Media type for a file the app has just saved, read off its own name.
String? mimeTypeForFileName(String fileName) {
  final parts = fileName.toLowerCase().split('.');
  if (parts.length < 2) return null;
  return _printerFileTypes[parts.last];
}
