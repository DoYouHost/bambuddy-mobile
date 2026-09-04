import 'dart:io';

import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'device_files.dart';

/// Getting something big out of the app: pull it down into a file, then let the
/// user say where it goes.
///
/// Two steps, both shared, because the alternative is what the printer's file
/// manager used to do — read the whole payload into memory and hand the bytes
/// to the system save dialog. `file_picker`'s `saveFile` cannot take anything
/// else on Android, which is why the save dialog here is
/// `flutter_file_dialog`'s: that one takes a *path* and copies it into the
/// chosen location with a stream on the platform side, so nothing the size of a
/// print ever passes through the phone's RAM.
///
/// The cache directory is the landing ground on purpose. The system may reclaim
/// it whenever it likes, which is right for a copy that exists only to be
/// passed on — the one that matters is the one the user saved or the receiving
/// app kept.
///
/// **Whether the caller may drop that copy itself depends on the hand-off, and
/// the two differ.** [saveDownloadedFile] has finished copying by the time it
/// returns, so its source is free the moment it does — a caller that downloads
/// under the file's own name should delete it, or it leaves one duplicate per
/// distinct name behind. [shareDownloadedFile] has *not* finished: the sheet
/// closes before the receiving app reads the URI, so deleting there is how a
/// share arrives empty. Only the first may clean up after itself; the second
/// really does have to wait for the system to reclaim it.

/// Streams a download into the cache directory under [scratchName], then
/// renames it to whatever [name] makes of the served `Content-Type`.
///
/// [download] is handed the path to write to and returns that content type. The
/// two-step rename exists because some routes only say what the file is *as*
/// they serve it — the timelapse route answers MP4, AVI or MKV from one URL —
/// and a file saved under the wrong extension is one nothing will open.
/// A download that fails takes its part-file with it: nothing here resumes one,
/// so what is left on disk is bytes no code path will ever read again. The
/// timelapse names its scratch after the archive, so without this every
/// interrupted video would keep its own partial copy — a full-size one, if the
/// connection dropped near the end.
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
  if (await target.exists()) await target.delete();
  return File(scratch).rename(target.path);
}

/// Drops a cache copy that has served its purpose, or was never going to.
///
/// Missing is not an error here — it is the wanted state, and the system may
/// have reclaimed the cache at any point on the way.
Future<void> discardCacheCopy(File file) async {
  try {
    await file.delete();
  } on FileSystemException {
    // Already gone.
  }
}

/// Hands [file] to the system share sheet.
///
/// [mimeType] decides which apps the sheet offers, so a ZIP announced as a
/// video reaches the wrong half of the phone. Null lets the platform guess from
/// the extension.
Future<void> shareDownloadedFile(File file, {String? mimeType}) =>
    SharePlus.instance.share(
      ShareParams(files: [XFile(file.path, mimeType: mimeType)]),
    );

/// Asks the user where to keep [file] and copies it there.
///
/// This is "Save as…", the dialog the download of a printer's file has always
/// ended in — not the share sheet, which offers whatever apps happen to be
/// installed and on a phone without Files by Google cannot save anything to
/// local storage at all.
///
/// [fileName] is the name suggested in the dialog; the user may change it.
///
/// Returns only once the copy is done, so [file] is the caller's to delete
/// straight after — on a cancel and a failure too, neither of which leaves the
/// dialog holding it.
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
/// both accept, for a file named after what it holds.
///
/// Strips the separators and wildcards that break a save (`/`, `\\`, `:`, `*`,
/// `?`), collapses runs of whitespace, and drops leading and trailing dots and
/// underscores — a leading dot makes a hidden file, and a trailing one collides
/// with whatever suffix the caller appends. `..` disappears with the
/// separators, so a name cannot walk out of the directory it is saved into.
///
/// [fallback] is the answer when nothing usable survives, which is why it has
/// no default: `timelapse` and `archive` are the right words in their own
/// places and the wrong one in the other's.
///
/// **Keeps letters and digits of any script.** `\w` is ASCII in Dart, so the
/// first cut of this reduced `Łódź` to `d` and a Japanese print name to nothing
/// — the fallback then named every one of them `timelapse.mp4`, which is how a
/// folder of saved videos becomes unusable in exactly the locales this app
/// ships in. `\p{L}\p{N}` needs `unicode: true` to mean anything; without the
/// flag Dart reads `\p` as a literal `p`.
///
/// Emoji and symbols still go: they are neither letter nor digit, and a share
/// target is entitled to refuse them.
String safeFileStem(String name, {required String fallback}) {
  final safe = name
      .replaceAll(RegExp(r'[^\p{L}\p{N}\s._-]', unicode: true), '')
      .trim()
      .replaceAll(RegExp(r'\s+'), '_')
      .replaceAll(RegExp(r'^[._]+|[._]+$'), '');
  return safe.isEmpty ? fallback : safe;
}

/// Media types for the files a printer keeps, by extension.
///
/// Only the ones the printer actually stores are listed; `null` for anything
/// else leaves the guess to the platform, which is a better answer than
/// declaring an octet-stream that some share targets refuse outright.
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
