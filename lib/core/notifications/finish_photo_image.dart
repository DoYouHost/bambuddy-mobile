import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../api/endpoints.dart';
import 'notification_service.dart';

/// Pulls a print's finish photo down to files a notification can be built from.
///
/// Two sizes, because a notification shows two: a full frame when expanded and a
/// square thumbnail while collapsed. Both are scaled down here — the bitmaps
/// travel inside the notification, which is mirrored to a paired watch over
/// Bluetooth. [photoWidth] is sized for the phone, the larger of the two screens
/// showing it: a watch fits it into 450–512 px, while on a phone the expanded
/// picture spans the screen width and anything smaller reads as soft.
class FinishPhotoImage {
  const FinishPhotoImage._();

  static const photoWidth = 1024;
  static const thumbnailWidth = 256;

  /// Downloads the photo and writes both sizes; null when anything fails — a
  /// notification without a picture is the working outcome here, never an error.
  static Future<AlertPicture?> store({
    required String baseUrl,
    required int archiveId,
    required String filename,
    required Dio dio,
    required Future<String> Function({bool forceRefresh}) token,
  }) async {
    try {
      final bytes = await _download(
        '$baseUrl${Endpoints.archivePhoto(archiveId, filename)}',
        dio,
        token,
      );
      if (bytes == null || bytes.isEmpty) return null;
      final dir = await getApplicationSupportDirectory();
      final photo = await _write(
        bytes,
        '${dir.path}/finish_photo.png',
        photoWidth,
      );
      if (photo == null) return null;
      return AlertPicture(
        photoPath: photo,
        thumbnailPath: await _write(
          bytes,
          '${dir.path}/finish_photo_thumb.png',
          thumbnailWidth,
        ),
      );
    } on Object {
      return null;
    }
  }

  /// GETs the image with `?token=` (camera token, not a header — same rule as
  /// thumbnails); on 401 mints a fresh token and retries once.
  static Future<Uint8List?> _download(
    String url,
    Dio dio,
    Future<String> Function({bool forceRefresh}) token,
  ) async {
    Future<Response<List<int>>> get(String t) => dio.get<List<int>>(
      url,
      queryParameters: {'token': t},
      options: Options(responseType: ResponseType.bytes),
    );

    try {
      final res = await get(await token());
      final data = res.data;
      return data == null ? null : Uint8List.fromList(data);
    } on DioException catch (e) {
      if (e.response?.statusCode != 401) rethrow;
      final res = await get(await token(forceRefresh: true));
      final data = res.data;
      return data == null ? null : Uint8List.fromList(data);
    }
  }

  /// Scales [bytes] down to [width] and writes them to [path], returning it.
  /// A photo already narrower than [width] is written as it came.
  ///
  /// Two isolates can reach the same fixed path, so the bytes go to a per-call
  /// temp file and are renamed into place — a rename inside one directory is
  /// atomic, and the decoder never sees a half-written file (same reason as
  /// `WidgetCoverCache`).
  static Future<String?> _write(Uint8List bytes, String path, int width) async {
    Uint8List data;
    try {
      data = await scaled(bytes, width);
    } on Object {
      // Decoding runs on whichever engine this isolate has; a photo at camera
      // resolution still beats no photo, and the platform scales notification
      // bitmaps down on its own anyway.
      data = bytes;
    }
    try {
      final tmp = File('$path.${DateTime.now().microsecondsSinceEpoch}.tmp');
      await tmp.writeAsBytes(data, flush: true);
      final file = await tmp.rename(path);
      return file.path;
    } on Object {
      return null;
    }
  }

  /// [bytes] scaled down to [width], or returned untouched when already that
  /// narrow. Aspect ratio is kept — only the width is asked for.
  @visibleForTesting
  static Future<Uint8List> scaled(Uint8List bytes, int width) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    try {
      if (descriptor.width <= width) return bytes;
      final codec = await descriptor.instantiateCodec(targetWidth: width);
      final frame = await codec.getNextFrame();
      try {
        final data = await frame.image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        // Re-encoding is the only step here that can come back empty rather
        // than throwing; the original is always a usable fallback.
        return data?.buffer.asUint8List() ?? bytes;
      } finally {
        frame.image.dispose();
        codec.dispose();
      }
    } finally {
      descriptor.dispose();
    }
  }
}
