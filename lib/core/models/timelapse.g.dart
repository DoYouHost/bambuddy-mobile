// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'timelapse.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TimelapseInfo _$TimelapseInfoFromJson(Map<String, dynamic> json) =>
    TimelapseInfo(
      duration: (json['duration'] as num).toDouble(),
      width: (json['width'] as num).toInt(),
      height: (json['height'] as num).toInt(),
      fps: (json['fps'] as num).toDouble(),
      codec: json['codec'] as String,
      fileSize: (json['file_size'] as num).toInt(),
      hasAudio: json['has_audio'] as bool,
    );

TimelapseProcessResult _$TimelapseProcessResultFromJson(
  Map<String, dynamic> json,
) => TimelapseProcessResult(
  status: json['status'] as String,
  message: json['message'] as String,
  outputPath: json['output_path'] as String?,
);
