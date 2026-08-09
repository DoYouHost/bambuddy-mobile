import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'diagnostic_recorder.dart';
import 'log_event.dart';

/// Records which screen the user is on, as `route` lines with `from` and `to`.
/// Without it `chrome.back` says nothing about what was left behind, and the
/// same `sheet.*` identifier shows up on several screens.
///
/// Reads the router's configuration rather than watching [Route] objects — a
/// route carries its *pattern* at best, and for a subroute only the relative
/// part. What the location cannot see (dialogs, sheets, menus) is
/// [ModalObserver]'s job.
class NavigationProbe {
  /// Kept current whether or not a recording is running, since the probe only
  /// reports the *next* change. Static so the recorder can reach it without
  /// depending on the router, which is rebuilt whenever the server profile
  /// changes — possibly mid-recording.
  static String? get screen => _screen;
  static String? _screen;

  GoRouterDelegate? _delegate;

  /// Starts following [router]. Call once, right after the router is built.
  void watch(GoRouter router) {
    _delegate = router.routerDelegate;
    // Saving a server profile rebuilds the router; clearing here would drop the
    // `from` of the transition that says the setup finally worked.
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

  /// `state.matchedLocation`, not `currentConfiguration.uri`: an imperative
  /// `push` — how nearly every screen here is opened — leaves that uri pointing
  /// at the screen *below*, which reads as "the user never went anywhere". It
  /// also carries no query string, where a model name sits.
  static String? _locationOf(GoRouterDelegate delegate) {
    // Empty until the first frame, and `state` throws on an empty configuration.
    if (delegate.currentConfiguration.isEmpty) return null;
    final path = delegate.state.matchedLocation;
    return path.isEmpty ? null : path;
  }
}

/// Records what gets pushed on top of a screen by hand — dialogs, sheets,
/// popup menus — as `open` and `close` lines with a `kind`.
///
/// **One instance per [Navigator].** Flutter asserts an observer belongs to a
/// single navigator, so a shared instance crashes the app on the second one.
/// Every shell branch needs its own: `showModalBottomSheet` pushes onto the
/// *nearest* navigator, which inside a tab is that tab's.
class ModalObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _log('open', route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _log('close', route);

  // didReplace and didRemove are left alone: go_router's screens are
  // [NavigationProbe]'s job, and nothing here replaces or removes a dialog.

  void _log(String evt, Route<dynamic> route) {
    // go_router builds every screen as a `Page` and those are reported by the
    // location instead. What is left was pushed by hand.
    if (route.settings is Page) return;
    DiagnosticRecorder.active?.add(
      LogSource.ui,
      evt,
      fields: {'kind': kindOf(route), 'name': route.settings.name},
    );
  }

  /// What kind of thing was pushed. Tested against the public route classes
  /// rather than type names, which a release build may obfuscate; `DialogRoute`
  /// and the popup menus arrive as subclasses of the two middle cases.
  static String kindOf(Route<dynamic> route) {
    if (route is ModalBottomSheetRoute) return 'sheet';
    if (route is RawDialogRoute) return 'dialog';
    if (route is PopupRoute) return 'popup';
    if (route is PageRoute) return 'page';
    return 'route';
  }
}
