import 'package:package_info_plus/package_info_plus.dart';

/// The running build as `version+buildNumber` — the spelling the bug-report
/// header, the About screen, the licence page, the drawer footer and the
/// watch's settings footer had each written out for themselves.
///
/// One spelling matters more than the five duplicated lines: a report quotes
/// this string back and somebody has to match it against a build. A sixth site
/// formatting it as `version (buildNumber)` would be a second thing to
/// recognise.
///
/// `PackageInfo.fromPlatform` caches the *value* statically, so the channel is
/// crossed once per process no matter how often this is called — but it is an
/// `async` function and hands back a **fresh future** every time, which is why
/// a widget still must not call it from `build`. Widgets read
/// `appVersionProvider` instead.
Future<String> readAppVersion() async {
  final info = await PackageInfo.fromPlatform();
  return '${info.version}+${info.buildNumber}';
}
