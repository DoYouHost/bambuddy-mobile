import 'dart:io';

import 'package:gal/gal.dart';

import '../../data/timelapse_repository.dart';
import '../common/file_export.dart';

/// Saving a timelapse out of the app: to the gallery, or to whatever the share
/// sheet offers.
///
/// Both start with the same download, because the video only exists on the
/// server and both destinations want a real file on disk. It streams into the
/// cache directory, which the system may reclaim — the copy that matters is
/// the one the gallery or the receiving app keeps.
class TimelapseExport {
  const TimelapseExport(this._repository);

  final TimelapseRepository _repository;

  /// Album the videos are grouped under in the gallery.
  static const _album = 'bambuddy';

  /// Throws [TimelapseGalleryDenied] when the device needs storage access for
  /// this and the user says no.
  ///
  /// Asked before the download, not after: on Android 10 and older, writing
  /// into an album is a storage write, and finding that out at the end would
  /// mean a hundred megabytes pulled for nothing.
  Future<void> saveToGallery(
    int archiveId, {
    required String token,
    required String name,
    void Function(double? progress)? onProgress,
  }) async {
    if (!await Gal.hasAccess(toAlbum: true) &&
        !await Gal.requestAccess(toAlbum: true)) {
      throw const TimelapseGalleryDenied();
    }
    final file = await _fetch(
      archiveId,
      token: token,
      name: name,
      onProgress: onProgress,
    );
    await Gal.putVideo(file.path, album: _album);
  }

  Future<void> share(
    int archiveId, {
    required String token,
    required String name,
    void Function(double? progress)? onProgress,
  }) async {
    final file = await _fetch(
      archiveId,
      token: token,
      name: name,
      onProgress: onProgress,
    );
    await shareDownloadedFile(file, mimeType: timelapseMimeType(file.path));
  }

  /// Downloads into a scratch file, then renames it to the print's name with
  /// the container the server actually served.
  ///
  /// The extension cannot be chosen up front: the same route hands over MP4,
  /// AVI (a P1S before the server's background conversion) or MKV, and a video
  /// filed in the gallery under the wrong extension is one nothing will open.
  Future<File> _fetch(
    int archiveId, {
    required String token,
    required String name,
    void Function(double? progress)? onProgress,
  }) => downloadToCacheFile(
    scratchName: 'timelapse-$archiveId.download',
    download: (savePath) => _repository.downloadTo(
      archiveId,
      token: token,
      savePath: savePath,
      // A server that streams without a length reports -1 as the total; the
      // bar goes indeterminate rather than jumping to a made-up fraction.
      onProgress: (received, total) =>
          onProgress?.call(total > 0 ? received / total : null),
    ),
    name: (contentType) =>
        exportFilename(name, timelapseExtension(contentType)),
  );
}

/// The device would not let the app write to the gallery. Distinct from a
/// failed download so the screen can say which of the two happened — one is
/// worth retrying, the other needs the user to change their mind.
class TimelapseGalleryDenied implements Exception {
  const TimelapseGalleryDenied();
}

/// Containers the server's timelapse route can serve, by the media type it
/// labels them with (`archives.py::get_timelapse`).
const _containers = {
  'video/mp4': 'mp4',
  'video/x-msvideo': 'avi',
  'video/x-matroska': 'mkv',
};

/// File extension for a served [contentType]; MP4 when the server says
/// nothing useful, which is what it serves for anything it cannot name.
String timelapseExtension(String? contentType) {
  final type = contentType?.split(';').first.trim().toLowerCase();
  return _containers[type] ?? 'mp4';
}

/// Media type for a file the app already named, read back off its extension —
/// the share sheet routes on this, so a `.avi` announced as MP4 offers the
/// wrong set of apps.
String timelapseMimeType(String path) {
  final extension = path.split('.').last.toLowerCase();
  for (final entry in _containers.entries) {
    if (entry.value == extension) return entry.key;
  }
  return 'video/mp4';
}

/// `<print name>_timelapse.<extension>`, with anything a filesystem or a share
/// target could choke on replaced. Mirrors the web UI's download name.
String exportFilename(String name, [String extension = 'mp4']) =>
    '${safeFileStem(name, fallback: 'timelapse')}_timelapse.$extension';
