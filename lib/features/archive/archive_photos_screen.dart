import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/endpoints.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../common/photo_pager.dart';
import '../common/dash_async.dart';
import 'archive_providers.dart';

/// Full-screen viewer for the photos of one print — in practice the shot the
/// server takes off the camera the moment the print finishes.
///
/// Like thumbnails and the timelapse, `GET /archives/{id}/photos/{name}` is
/// gated on the media credential rather than on the Bearer header, so the URL
/// is built here instead of going through the Dio client.
///
/// The photo list is re-read from the server rather than carried in from the
/// archive list: the finish photo is attached in a background task seconds to
/// minutes after the print ends, so a list loaded earlier can be missing it.
class ArchivePhotosScreen extends ConsumerWidget {
  const ArchivePhotosScreen({super.key, required this.archiveId, this.title});

  final int archiveId;

  /// Title on the bar (the print name); falls back to l10n.
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final archive = ref.watch(archiveDetailProvider(archiveId));

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: photoViewerAppBar(title ?? l10n.archivePhotosTitle),
      body: dashAsync(
        context,
        archive,
        onRetry: () => ref.invalidate(archiveDetailProvider(archiveId)),
        skipLoadingOnReload: false,
        skipLoadingOnRefresh: false,
        data: (a) => a.hasPhotos
            ? PhotoPager(
                paths: [
                  for (final name in a.photos)
                    Endpoints.archivePhoto(a.id, name),
                ],
              )
            : EmptyStateView(
                message: l10n.archivePhotosEmpty,
                icon: Icons.photo_camera_outlined,
              ),
      ),
    );
  }
}
