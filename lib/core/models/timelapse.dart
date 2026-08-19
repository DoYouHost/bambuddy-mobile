import 'dart:convert';
import 'dart:typed_data';

import 'package:json_annotation/json_annotation.dart';

part 'timelapse.g.dart';

/// What ffprobe found in the recording (`TimelapseInfoResponse`).
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class TimelapseInfo {
  const TimelapseInfo({
    required this.duration,
    required this.width,
    required this.height,
    required this.fps,
    required this.codec,
    required this.fileSize,
    required this.hasAudio,
  });

  factory TimelapseInfo.fromJson(Map<String, dynamic> json) =>
      _$TimelapseInfoFromJson(json);

  /// Length in seconds.
  final double duration;

  final int width;
  final int height;
  final double fps;

  /// Codec name as ffprobe spells it (e.g. "h264").
  final String codec;

  final int fileSize;
  final bool hasAudio;
}

/// Filmstrip frames for the editor (`ThumbnailResponse`): JPEGs the server
/// hands over base64-encoded, each with the second it was taken at.
class TimelapseFilmstrip {
  const TimelapseFilmstrip({required this.frames, required this.timestamps});

  /// Skips a frame the server encoded in a way we cannot decode rather than
  /// losing the whole strip over one of fourteen images.
  factory TimelapseFilmstrip.fromJson(Map<String, dynamic> json) {
    final raw = (json['thumbnails'] as List<dynamic>? ?? const [])
        .whereType<String>();
    final stamps = (json['timestamps'] as List<dynamic>? ?? const [])
        .whereType<num>()
        .map((t) => t.toDouble())
        .toList();
    final frames = <Uint8List>[];
    for (final encoded in raw) {
      try {
        frames.add(base64Decode(encoded));
      } on FormatException {
        continue;
      }
    }
    return TimelapseFilmstrip(frames: frames, timestamps: stamps);
  }

  final List<Uint8List> frames;
  final List<double> timestamps;

  bool get isEmpty => frames.isEmpty;
}

/// Where a processed video ended up (`ProcessResponse`).
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class TimelapseProcessResult {
  const TimelapseProcessResult({
    required this.status,
    required this.message,
    this.outputPath,
  });

  factory TimelapseProcessResult.fromJson(Map<String, dynamic> json) =>
      _$TimelapseProcessResultFromJson(json);

  /// "completed" or "error" — the server answers only when ffmpeg is done.
  final String status;

  final String message;
  final String? outputPath;

  bool get ok => status == 'completed';
}
