import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/api/endpoints.dart';
import '../../core/models/archive.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import '../../providers.dart';
import '../common/camera_token_image_recovery.dart';
import '../common/state_views.dart';
import 'archive_providers.dart';

/// Full-screen viewer for the photos of one print — in practice the shot the
/// server takes off the camera the moment the print finishes.
///
/// Like thumbnails and the timelapse, `GET /archives/{id}/photos/{name}` is
/// gated on the camera stream token in `?token=` rather than on the auth
/// header, so the URL is built here instead of going through the Dio client.
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
      appBar: loggedAppBar(
        AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
          title: Text(
            title ?? l10n.archivePhotosTitle,
            style: const TextStyle(
              fontFamily: DashTokens.fontUi,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: Colors.white,
            ),
          ),
        ),
      ),
      body: archive.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AsyncErrorView(
          message: e is AppApiException ? e.localized(l10n) : l10n.connectFailed,
          retryLabel: l10n.retry,
          onRetry: () => ref.invalidate(archiveDetailProvider(archiveId)),
        ),
        data: (a) => a.hasPhotos
            ? _PhotoPager(archive: a)
            : EmptyStateView(
                message: l10n.archivePhotosEmpty,
                icon: Icons.photo_camera_outlined,
              ),
      ),
    );
  }
}

/// Swipeable pages, one photo each, with the position shown while there is
/// more than one to swipe through.
class _PhotoPager extends StatefulWidget {
  const _PhotoPager({required this.archive});

  final Archive archive;

  @override
  State<_PhotoPager> createState() => _PhotoPagerState();
}

class _PhotoPagerState extends State<_PhotoPager> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final photos = widget.archive.photos;
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        PageView.builder(
          itemCount: photos.length,
          onPageChanged: (i) => setState(() => _page = i),
          itemBuilder: (_, i) =>
              _Photo(archiveId: widget.archive.id, filename: photos[i]),
        ),
        if (photos.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Text(
                  '${_page + 1} / ${photos.length}',
                  style: const TextStyle(
                    fontFamily: DashTokens.fontMono,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// One photo, pinch-zoomable. A lapsed camera token fails the same way a
/// missing file does, so [CameraTokenImageRecovery] re-mints once and the new
/// URL reloads the image.
class _Photo extends ConsumerStatefulWidget {
  const _Photo({required this.archiveId, required this.filename});

  final int archiveId;
  final String filename;

  @override
  ConsumerState<_Photo> createState() => _PhotoState();
}

class _PhotoState extends ConsumerState<_Photo> with CameraTokenImageRecovery {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final baseUrl = ref.watch(serverProfileProvider)?.baseUrl;
    if (baseUrl == null) {
      return _message(l10n.archivePhotoFailed);
    }

    return ref
        .watch(cameraTokenProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => _message(l10n.archivePhotoFailed),
          data: (token) => InteractiveViewer(
            maxScale: 5,
            child: Image.network(
              '$baseUrl${Endpoints.archivePhoto(widget.archiveId, widget.filename)}'
              '?token=$token',
              fit: BoxFit.contain,
              width: double.infinity,
              height: double.infinity,
              gaplessPlayback: true,
              errorBuilder: (_, error, _) {
                recoverCameraTokenOnError(error, token);
                return _message(l10n.archivePhotoFailed);
              },
              loadingBuilder: (_, child, progress) => progress == null
                  ? child
                  : const Center(child: CircularProgressIndicator()),
            ),
          ),
        );
  }

  Widget _message(String text) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white70),
      ),
    ),
  );
}
