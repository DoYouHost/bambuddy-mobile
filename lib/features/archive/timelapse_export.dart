import 'dart:io';

import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/timelapse_repository.dart';

/// Saving a timelapse out of the app: to the gallery, or to whatever the share
/// sheet offers.
///
/// Both start with the same download, because the video only exists on the
/// server and both destinations want a real file on disk. It lands in the
/// cache directory, which the system may reclaim — the copy that matters is
/// the one the gallery or the receiving app keeps.
class TimelapseExport {
  const TimelapseExport(this._repository);

  final TimelapseRepository _repository;

  /// Album the videos are grouped under in the gallery.
  static const _album = 'bambuddy';

  Future<void> saveToGallery(
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
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path, mimeType: 'video/mp4')]),
    );
  }

  Future<File> _fetch(
    int archiveId, {
    required String token,
    required String name,
    void Function(double? progress)? onProgress,
  }) async {
    final bytes = await _repository.download(
      archiveId,
      token: token,
      // A server that streams without a length reports -1 as the total; the
      // bar goes indeterminate rather than jumping to a made-up fraction.
      onProgress: (received, total) =>
          onProgress?.call(total > 0 ? received / total : null),
    );
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${exportFilename(name)}');
    await file.writeAsBytes(bytes);
    return file;
  }
}

/// `<print name>_timelapse.mp4`, with anything a filesystem or a share target
/// could choke on replaced. Mirrors the web UI's download name.
String exportFilename(String name) {
  final safe = name
      .replaceAll(RegExp(r'[^\w\s.-]'), '')
      .trim()
      // Leading dots would make it a hidden file; a trailing one (or the
      // underscore a trailing space turns into) collides with the suffix.
      .replaceAll(RegExp(r'\s+'), '_')
      .replaceAll(RegExp(r'^[._]+|[._]+$'), '');
  return '${safe.isEmpty ? 'timelapse' : safe}_timelapse.mp4';
}
