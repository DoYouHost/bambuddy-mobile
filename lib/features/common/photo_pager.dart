import 'package:flutter/material.dart';

import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import 'media_image.dart';

/// The bar over a full-screen photo: transparent on black, white type.
PreferredSizeWidget photoViewerAppBar(String title, {List<Widget>? actions}) =>
    loggedAppBar(
      AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        actions: actions,
        title: Text(
          title,
          style: const TextStyle(
            fontFamily: DashTokens.fontUi,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            color: Colors.white,
          ),
        ),
      ),
    );

/// Swipeable pages, one photo each, with the position shown while there is
/// more than one to swipe through. [paths] are media routes, served through
/// [MediaImage].
class PhotoPager extends StatefulWidget {
  const PhotoPager({
    super.key,
    required this.paths,
    this.initialPage = 0,
    this.onPageChanged,
  });

  final List<String> paths;
  final int initialPage;
  final ValueChanged<int>? onPageChanged;

  @override
  State<PhotoPager> createState() => _PhotoPagerState();
}

class _PhotoPagerState extends State<PhotoPager> {
  late int _page = widget.initialPage;
  late final _controller = PageController(initialPage: widget.initialPage);

  @override
  void didUpdateWidget(PhotoPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The list can shrink under an open viewer (a photo deleted elsewhere);
    // the PageView settles on its last page, the counter has to follow.
    if (_page >= widget.paths.length && widget.paths.isNotEmpty) {
      _page = widget.paths.length - 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.paths;
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        PageView.builder(
          controller: _controller,
          itemCount: photos.length,
          onPageChanged: (i) {
            setState(() => _page = i);
            widget.onPageChanged?.call(i);
          },
          itemBuilder: (_, i) => _Photo(path: photos[i]),
        ),
        if (photos.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: DashSpace.xl),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: DashSpace.md,
                  vertical: DashSpace.sm,
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

/// One photo, pinch-zoomable. A lapsed media token fails the same way a
/// missing file does, so [MediaImage] re-mints once and the new URL reloads
/// the picture.
class _Photo extends StatelessWidget {
  const _Photo({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return InteractiveViewer(
      maxScale: 5,
      child: MediaImage(
        path: path,
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
        placeholder: (status) => status == MediaImageStatus.loading
            ? const DashLoading()
            : _message(l10n.archivePhotoFailed),
      ),
    );
  }

  Widget _message(String text) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: DashSpace.xl),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white70),
      ),
    ),
  );
}
