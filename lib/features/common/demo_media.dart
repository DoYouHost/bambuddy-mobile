import '../../core/demo/demo_backend.dart';

/// The bundled picture that stands in for an image route of the demo server,
/// or null where the real server would have none either.
///
/// Phone-only on purpose: the watch build prunes `assets/demo/`, and
/// `tool/check_wear_apk.py` fails if this path reaches the watch snapshot.
String? demoAssetFor(String route) {
  final picture = DemoBackend.instance.pictureFor(route);
  return picture == null ? null : 'assets/demo/$picture.webp';
}

/// The demo camera's frames for [printerId], as asset paths — a loop while
/// the printer prints, one still otherwise, none when it has no picture.
List<String> demoCameraFrames(int printerId) => [
  for (final frame in DemoBackend.instance.cameraFrames(printerId))
    'assets/demo/$frame.webp',
];
