import 'dart:async';

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
  ObservedCapability(this._feature, this._version, {this.whenUnknown = false})
    : _probe = null;

  /// No version row behind it, for a route that predates every server this app
  /// talks to: a threshold could then only hide it from a healthy server whose
  /// version read failed. The permission is still worth watching.
  ///
  /// [probe] is a request that settles this latch — it must go through
  /// [watching] — for a gate that cannot wait until a screen happens to call
  /// the route (see [probeIfUnknown]).
  ObservedCapability.unversioned({this.whenUnknown = true, this._probe})
    : _feature = null,
      _version = null;

  final ServerFeature? _feature;
  final ServerVersionService? _version;
  final Future<void> Function()? _probe;

  /// The answer while nothing has been observed and no version is known:
  /// `false` where offering a control an older server would silently ignore
  /// costs more than hiding one, `true` where hiding it costs more.
  final bool whenUnknown;

  bool? _observed;
  bool _refused = false;
  bool _probing = false;
  bool _probeFailed = false;
  int? _failedAtEpoch;
  final _listeners = <void Function()>[];

  /// The version row a synchronous reader should consult, or `null` when there
  /// is none to consult — no row, or no version service, which [supported]
  /// also answers with [whenUnknown].
  ServerFeature? get feature => _version == null ? null : _feature;

  /// What the server itself said: `false` after a refusal, the observation
  /// otherwise, `null` while it has said nothing.
  bool? get observedAnswer => _refused ? false : _observed;

  bool get canProbe => _probe != null;

  /// The last probe ended without the server saying anything (no network, 5xx,
  /// 401). Stays set while a re-probe is in flight, so a gate keeps its
  /// settled answer rather than going back to loading.
  bool get probeFailed => _probeFailed;

  /// Called after [observedAnswer] or [probeFailed] changed. Never from inside
  /// a call a provider build makes: observations land after an `await`, and a
  /// probe reports on completion.
  void addListener(void Function() listener) => _listeners.add(listener);

  void removeListener(void Function() listener) => _listeners.remove(listener);

  void _update(void Function() change) {
    final before = (observedAnswer, _probeFailed);
    change();
    if ((observedAnswer, _probeFailed) == before) return;
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  void observe({required bool present}) => _update(() {
    _observed = present;
    _probeFailed = false;
    if (present) _refused = false;
  });

  void observeRefusal() => _update(() {
    _refused = true;
    _probeFailed = false;
  });

  /// Sends the probe unless something has already been heard, one is in flight,
  /// or one already went unanswered at this [epoch] — the count of regained
  /// contacts. Without that last condition a failed probe would notify, the
  /// gate would rebuild and probe again, as fast as the network can fail.
  void probeIfUnknown({required int epoch}) {
    final probe = _probe;
    if (probe == null || observedAnswer != null) return;
    if (_probing || _failedAtEpoch == epoch) return;
    _probing = true;
    unawaited(_runProbe(probe, epoch));
  }

  Future<void> _runProbe(Future<void> Function() probe, int epoch) async {
    try {
      await probe();
    } on Object {
      // Whatever the status said, [watching] has already recorded it.
    }
    _probing = false;
    if (observedAnswer != null) return;
    _failedAtEpoch = epoch;
    _update(() => _probeFailed = true);
  }

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
