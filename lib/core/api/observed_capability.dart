import 'package:dio/dio.dart';

import 'api_exceptions.dart';
import 'server_version.dart';
import 'server_version_service.dart';

/// A server capability the app settles by watching what the server actually
/// answers, with [ServerVersion.introducedIn] behind it for before anything has
/// been seen.
///
/// The shape was written out six times before it lived here, always because a
/// version number cannot always answer the question — bambuddy renumbered the
/// 0.2.5 cycle to 1.2.5 partway through, and every 1.2.6 daily build reports
/// `1.2.6b1` — while a field's type or a route's 404 can. Three answers, in
/// this order:
///
/// 1. **A refusal outranks everything.** A 403 says the route is there and this
///    session may not use it: a question no version can answer, and one that
///    must not be recorded as an observation about the route itself.
/// 2. **What was observed outranks the version**, being the same question
///    answered outright rather than inferred from a number.
/// 3. **The version table, and [whenUnknown] behind it** — for before the first
///    reply, and for callers with no version service at all (the watch relay
///    and the background isolate never build one).
///
/// Every latch lives as long as the instance, which is the intended lifetime:
/// the repositories are rebuilt when `apiClientProvider` changes, and the ones
/// behind a chart also on the dashboard's pull-to-refresh — the only in-app way
/// to notice a permission granted server-side, since a control that hid itself
/// never calls its route again.
///
/// Two gates deliberately stay outside it: `StatsRepository._hasSlimListing`
/// (its version row must not be consulted — see
/// [ServerFeature.usersSlimListing]) and `offlinePlateClearProvider`, which
/// latches per server profile rather than per instance.
class ObservedCapability {
  /// [version] is nullable rather than optional so that a caller which has one
  /// cannot forget to pass it: every construction states its fallback.
  ObservedCapability(this._feature, this._version, {this.whenUnknown = false});

  /// A capability with no version row behind it, because its route predates
  /// every server this app talks to: a threshold could then only ever hide it
  /// from a healthy server whose version read failed. What is still worth
  /// watching is the permission (`AmsHistoryRepository`).
  ObservedCapability.unversioned({this.whenUnknown = true})
      : _feature = null,
        _version = null;

  final ServerFeature? _feature;
  final ServerVersionService? _version;

  /// The answer while nothing has been observed and no version is known.
  /// `false` where offering a control an older server would refuse — or, worse,
  /// silently ignore — costs more than hiding one; `true` where hiding it takes
  /// a working feature off a server whose version read merely failed.
  final bool whenUnknown;

  bool? _observed;
  bool _refused = false;

  /// Records what a reply showed. A reply that arrived at all also says this
  /// caller is not refused, so `present: true` clears [observeRefusal].
  void observe({required bool present}) {
    _observed = present;
    if (present) _refused = false;
  }

  /// The route is there, but this session may not use it (403).
  void observeRefusal() => _refused = true;

  /// Records what [status] said about the route: a **404** is the route not
  /// being there, a **403** is it not being for this caller, and anything else
  /// (401, 5xx, no response at all) says nothing about either and must pin
  /// neither latch.
  void observeFailure(int? status) {
    switch (status) {
      case 404:
        observe(present: false);
      case 403:
        observeRefusal();
    }
  }

  /// Runs [request] with this latch watching what came back, and maps a
  /// failure the way every repository here maps one.
  ///
  /// The wrapper is for the middle of it. The two statuses [observeFailure]
  /// reads are also the two a caller usually has a plain answer for, and the
  /// try/catch that says so was written out at ten call sites in seven
  /// repositories — which is how one of them ends up recording a 403 and
  /// another forgetting to.
  ///
  /// [absent] is what to answer with instead of throwing for the statuses in
  /// [absentOn]. Passing none throws everything, which is right where the latch
  /// only hides a control: the request is then one the user asked for, and a
  /// refusal has to reach them.
  ///
  /// [absentOn] drops to `{404}` for exactly that reason — a route behind a
  /// button the user pressed. A 403 there does not mean "nothing to show", it
  /// means "you may not", and answering it with [absent] leaves a control that
  /// does nothing and never says why.
  ///
  /// [observing] narrows which statuses may *settle* the latch, where
  /// [absentOn] only picks what to answer with. It drops to `{403}` for a
  /// route addressed by row id: there a 404 is the row being gone, not the
  /// route being absent, and recording it as absence hides the whole
  /// capability the first time a stale id is opened.
  Future<T> watching<T>(
    Future<T> Function() request, {
    T Function()? absent,
    Set<int> absentOn = const {404, 403},
    Set<int> observing = const {404, 403},
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
