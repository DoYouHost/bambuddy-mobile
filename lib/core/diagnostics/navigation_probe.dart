import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'diagnostic_recorder.dart';
import 'log_event.dart';

/// Records which screen the user is on, as `route` lines with `from` and `to`.
///
/// A tap records an identifier and a role and nothing else (labels are not
/// logged at all), so without the screen the log is only half-readable:
/// `chrome.back` says nothing about what was left behind, and the same `sheet.*`
/// identifier shows up on several screens.
///
/// Reads the router's own configuration rather than watching [Route] objects: a
/// route carries its *pattern* at best, and for a subroute only the relative
/// part of it — the path lives in the location. What the location cannot see —
/// dialogs, sheets and menus, which leave it untouched — is [ModalObserver]'s
/// job.
///
/// Installed for the app's lifetime and writing through
/// `DiagnosticRecorder.active`, which is null unless a recording runs.
class NavigationProbe {
  /// The screen the app is showing, kept current whether or not a recording is
  /// running: a session started on the archive has to say so in its first
  /// records, and the probe only ever reports the *next* change.
  ///
  /// Static so the recorder can reach it without depending on the router, which
  /// is rebuilt whenever the server profile changes — possibly mid-recording.
  static String? get screen => _screen;
  static String? _screen;

  GoRouterDelegate? _delegate;

  /// Starts following [router]. Call once, right after the router is built.
  void watch(GoRouter router) {
    _delegate = router.routerDelegate;
    // Keep the screen the user is looking at when the new router has not
    // resolved one yet. Saving a server profile rebuilds the router, and
    // clearing here would drop the `from` of the very transition that says the
    // setup finally worked.
    _screen = _locationOf(router.routerDelegate) ?? _screen;
    router.routerDelegate.addListener(_onRouterChanged);
  }

  void unwatch() {
    _delegate?.removeListener(_onRouterChanged);
    _delegate = null;
  }

  void _onRouterChanged() {
    final delegate = _delegate;
    if (delegate == null) return;
    final to = _locationOf(delegate);
    // Redirects and imperative pushes can settle on the location already
    // showing; one record per actual change.
    if (to == null || to == _screen) return;
    final from = _screen;
    _screen = to;
    DiagnosticRecorder.active?.add(
      LogSource.ui,
      'route',
      fields: {'from': from, 'to': to},
    );
  }

  /// The topmost screen's path.
  ///
  /// `state.matchedLocation`, not `currentConfiguration.uri`: an imperative
  /// `push` — which is how nearly every screen in this app is opened — leaves the
  /// configuration's uri pointing at the screen *below*, so that reads as "the
  /// user never went anywhere". `matchedLocation` also carries no query string,
  /// where a model name sits (`/gcode-viewer?name=…`).
  static String? _locationOf(GoRouterDelegate delegate) {
    // Empty until the first frame, and `state` throws on an empty configuration.
    if (delegate.currentConfiguration.isEmpty) return null;
    final path = delegate.state.matchedLocation;
    return path.isEmpty ? null : path;
  }
}

/// Records what gets pushed on top of a screen by hand — dialogs, bottom sheets,
/// popup menus — as `open` and `close` lines with a `kind`.
///
/// **One instance per [Navigator].** Flutter asserts that an observer belongs to
/// a single navigator, so the root navigator and every shell branch get their
/// own; a shared instance crashes the app on the second one. There is no state
/// to share anyway — the records go through `DiagnosticRecorder.active`.
///
/// Every branch needs one: `showModalBottomSheet` pushes onto the *nearest*
/// navigator, which inside a tab is that tab's own.
class ModalObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _log('open', route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _log('close', route);

  // didReplace and didRemove are deliberately left alone: go_router's own
  // screens are [NavigationProbe]'s job, and nothing in the app replaces or
  // silently removes a dialog.

  void _log(String evt, Route<dynamic> route) {
    // go_router builds every screen as a `Page`, and those are reported by the
    // location instead. What is left is what was pushed by hand: dialogs,
    // sheets, menus, `showLicensePage`.
    if (route.settings is Page) return;
    DiagnosticRecorder.active?.add(
      LogSource.ui,
      evt,
      fields: {'kind': kindOf(route), 'name': route.settings.name},
    );
  }

  /// What kind of thing was pushed. Tested against the public route classes
  /// rather than type names, which a release build may obfuscate.
  static String kindOf(Route<dynamic> route) {
    if (route is ModalBottomSheetRoute) return 'sheet';
    if (route is RawDialogRoute) return 'dialog'; // DialogRoute extends it
    if (route is PopupRoute) return 'popup'; // popup menus, old dropdowns
    if (route is PageRoute) return 'page';
    return 'route';
  }
}
