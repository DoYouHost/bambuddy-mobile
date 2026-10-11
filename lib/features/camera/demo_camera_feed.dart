import 'dart:async';

import 'package:flutter/material.dart';

import '../common/demo_media.dart';

/// The demo's camera: the frames it ships for the printer, cycled at the two
/// frames a second a busy chamber stream manages. [empty] stands in for a
/// printer with no picture at all.
class DemoCameraFeed extends StatefulWidget {
  const DemoCameraFeed({
    super.key,
    required this.printerId,
    required this.empty,
    this.fit = BoxFit.contain,
    this.cacheWidth,
  });

  static const frameEvery = Duration(milliseconds: 500);

  final int printerId;
  final Widget empty;
  final BoxFit fit;
  final int? cacheWidth;

  @override
  State<DemoCameraFeed> createState() => _DemoCameraFeedState();
}

class _DemoCameraFeedState extends State<DemoCameraFeed> {
  late final List<String> _frames = demoCameraFrames(widget.printerId);
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    if (_frames.length > 1) {
      _timer = Timer.periodic(
        DemoCameraFeed.frameEvery,
        (_) => setState(() => _index = (_index + 1) % _frames.length),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Decoded up front, or the first pass through the loop flickers while
    // each frame loads.
    for (final frame in _frames.skip(1)) {
      unawaited(precacheImage(_provider(frame), context));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  ImageProvider _provider(String asset) =>
      ResizeImage.resizeIfNeeded(widget.cacheWidth, null, AssetImage(asset));

  @override
  Widget build(BuildContext context) {
    if (_frames.isEmpty) return widget.empty;
    return Image(
      image: _provider(_frames[_index]),
      fit: widget.fit,
      gaplessPlayback: true,
    );
  }
}
