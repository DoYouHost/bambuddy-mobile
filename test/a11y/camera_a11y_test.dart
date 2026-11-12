import 'dart:async';

import 'package:bambuddy_mobile/features/camera/camera_view.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers.dart';
import 'a11y_harness.dart';

/// Rendered contrast and touch targets of the full-screen camera view, on the
/// demo's own frames (printer 1 streams, printer 3 has none) and on the token
/// states the live view passes through. Not covered: the live MJPEG picture
/// itself and the wall tile's snapshot fallback, which need a socket to a
/// camera and draw pixels no widget test can produce.
void main() {
  a11ySurface(
    'camera, demo frame',
    home: () => const CameraView(printerId: 1, printerName: 'X1 Carbon'),
    shows: find.text('X1 Carbon'),
  );

  a11ySurface(
    'camera, demo printer without a picture',
    home: () => const CameraView(printerId: 3, printerName: 'A1 mini'),
    shows: find.text(pl.cameraDemoUnavailable),
  );

  a11ySurface(
    'camera, connecting',
    demo: false,
    overrides: [
      fakeServerProfileOverride(),
      cameraTokenProvider.overrideWith((ref) => Completer<String>().future),
    ],
    home: () => const CameraView(printerId: 1, printerName: 'X1 Carbon'),
    shows: find.text(pl.cameraConnecting),
  );

  a11ySurface(
    'camera, stream refused',
    demo: false,
    overrides: [
      fakeServerProfileOverride(),
      cameraTokenProvider.overrideWith(
        (ref) => throw Exception('auth failure'),
      ),
    ],
    home: () => const CameraView(printerId: 1, printerName: 'X1 Carbon'),
    shows: byLogId('camera.retry'),
  );

  // The badge MjpegView draws over the frozen last frame while it retries.
  a11ySurface(
    'camera, retrying badge',
    home: () => const Scaffold(
      backgroundColor: Colors.black,
      body: Align(alignment: Alignment.topLeft, child: CameraRetryingBadge()),
    ),
    shows: find.byType(CameraRetryingBadge),
  );
}
