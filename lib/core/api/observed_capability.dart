import 'package:dio/dio.dart';

import 'api_exceptions.dart';
import 'server_version.dart';
import 'server_version_service.dart';

/// [ObservedCapability.watching]'s `observing` for a route whose 404 can only
/// mean the route is not there, because it looks no row up.
///
/// Read off the handler rather than assumed: one calling `_load_printer_or_404`,
/// `_ensure_archive_visible` or their like has a second reason to answer 404
/// and keeps the default.
const treat404AsAbsent = {404, 403};

/// A server capability the app settles by watching what the server actually
/// answers, with [ServerVersion.introducedIn] behind it for before anything has
/// been seen — a version number cannot always answer the question (see
/// [ServerVersion]), while a route's 403 or 404 can. In order: a refusal, then
/// what was observed, then the version table and [whenUnknown] behind it.
///
/// A latch lives as long as the instance. That is the intended lifetime: the
/// repositories are rebuilt when `apiClientProvider` changes, which is the only
/// in-app way to notice a permission granted server-side — a control that hid
/// itself never calls its route again.
///
/// Two gates deliberately stay outside it: `StatsRepository._hasSlimListing`
/// (its version row must not be consulted — see
/// [ServerFeature.usersSlimListing]) and `offlinePlateClearProvider`, which
/// latches per server profile rather than per instance.
class ObservedCapability {
  /// [version] is nullable rather than optional so that a caller which has one
  /// cannot forget to pass it: every construction states its fallback.
  ObservedCapability(this._feature, this._version, {this.whenUnknown = false});

  /// No version row behind it, for a route that predates every server this app
  /// talks to: a threshold could then only hide it from a healthy server whose
  /// version read failed. The permission is still worth watching.
  ObservedCapability.unversioned({this.whenUnknown = true})
    : _feature = null,
      _version = null;

  final ServerFeature? _feature;
  final ServerVersionService? _version;

  /// The answer while nothing has been observed and no version is known:
  /// `false` where offering a control an older server would silently ignore
  /// costs more than hiding one, `true` where hiding it costs more.
  final bool whenUnknown;

  bool? _observed;
  bool _refused = false;

  void observe({required bool present}) {
    _observed = present;
    if (present) _refused = false;
  }

  void observeRefusal() => _refused = true;

  /// A **404** is the route not being there, a **403** is it not being for this
  /// caller; anything else (401, 5xx, no response) says nothing about either.
  void observeFailure(int? status) {
    switch (status) {
      case 404:
        observe(present: false);
      case 403:
        observeRefusal();
    }
  }

  /// Runs [request] with this latch watching what came back, and maps a failure
  /// the way every repository here maps one.
  ///
  /// [absent] answers instead of throwing for the statuses in [absentOn];
  /// passing none throws everything, which is right behind a button the user
  /// pressed — a refusal has to reach them rather than leave a control that
  /// does nothing. [observing] narrows which statuses may *settle* the latch,
  /// and defaults to a refusal only: most of these routes are addressed by a
  /// row id, where a 404 is that row being gone, not the route. Pass
  /// [treat404AsAbsent] on one that looks no row up.
  Future<T> watching<T>(
    Future<T> Function() request, {
    T Function()? absent,
    Set<int> absentOn = const {404, 403},
    Set<int> observing = const {403},
  }) async {
    try {
      final answer = await request();
      observe(present: true);
      return answer;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (observing.contains(status)) observeFailure(status);
      if (absent != null && absentOn.contains(status)) return absent();
      throw mapDioException(e);
    }
  }

  /// Whether to offer the capability, resolved in the order documented above.
  Future<bool> get supported async {
    if (_refused) return false;
    final observed = _observed;
    if (observed != null) return observed;
    final feature = _feature;
    final version = _version;
    if (feature == null || version == null) return whenUnknown;
    return (await version.current())?.supports(feature) ?? whenUnknown;
  }
}
