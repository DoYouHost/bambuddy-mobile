import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/timelapse.dart';
import '../../providers.dart';

/// ffprobe metadata for one recording — the editor reads its duration.
final timelapseInfoProvider = FutureProvider.autoDispose
    .family<TimelapseInfo, int>(
      (ref, archiveId) =>
          ref.watch(timelapseRepositoryProvider).info(archiveId),
    );

/// Filmstrip behind the trim range. Separate from [timelapseInfoProvider]
/// because the server renders every frame with ffmpeg on request: the editor
/// can draw its slider from the duration alone while these are still coming.
final timelapseFilmstripProvider = FutureProvider.autoDispose
    .family<TimelapseFilmstrip, int>(
      (ref, archiveId) =>
          ref.watch(timelapseRepositoryProvider).filmstrip(archiveId),
    );
