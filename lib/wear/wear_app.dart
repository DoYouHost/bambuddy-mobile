import 'dart:async';

import 'package:clock/clock.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_context.dart';
import '../core/format/datetime_format.dart';
import '../core/watch/watch_config_sync.dart';
import '../l10n/app_localizations.dart';
import '../providers.dart';
import 'screens/wear_home.dart';
import 'screens/wear_setup_screen.dart';
import 'wear_colours.dart';
import 'wear_ongoing.dart';
import 'wear_providers.dart';
import 'wear_shape.dart';
import 'wear_theme.dart';
import 'wear_transport.dart';

/// Root of the Wear app. Routes purely on whether a server profile exists —
/// no bottom nav, no drawer; drill-down uses a plain [Navigator]. The look lives
/// in [wearTheme].
///
/// Also the receiver end of the phone→watch config handoff: on launch it reads
/// any latched config and listens for live pushes, so the user never has to type
/// the server details on the watch. What arrives is adopted straight away only
/// when it names the server already in use; a different one is offered through
/// [pendingWatchConfigProvider] and waits for a tap — see [_routeConfig].
class WearApp extends ConsumerStatefulWidget {
  const WearApp({super.key});

  @override
  ConsumerState<WearApp> createState() => _WearAppState();
}

class _WearAppState extends ConsumerState<WearApp> with WidgetsBindingObserver {
  StreamSubscription<WatchConfig>? _configSub;

  /// Live while the app is in the background with a print running.
  ProviderSubscription<AsyncValue<WearFleet>>? _ongoingSub;

  /// Set by the first live push, which is newer than anything latched.
  var _livePushSeen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ingestPendingConfig();
    _configSub = ref.read(watchConfigSyncProvider).configStream().listen((
      config,
    ) {
      _livePushSeen = true;
      _routeConfig(config);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _configSub?.cancel();
    _ongoingSub?.close();
    _ongoingSub = null;
    super.dispose();
  }

  /// Coming back to the foreground → fetch immediately, and going away → stop
  /// polling until then — unless a print is running, which Play's WO-V4 wants
  /// on the watch face as an Ongoing Activity, fed by a slow background poll
  /// (docs/wear-fleet-poll.md, "Background").
  ///
  /// The OS freezes the app eventually, but not at once, and until it does every
  /// tick wakes the phone over the bridge for a screen that is off. Relying on
  /// that freeze is what left the watch polling a darkened face; the phone's own
  /// long-lived screens have paused their timers explicitly since they were
  /// written (`pipeline_runs_screen`, `queue_screen`).
  ///
  /// Guarded by `exists` so it never *creates* the fleet provider (e.g. while
  /// still on the setup screen).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!ref.exists(wearFleetProvider)) return;
    final fleet = ref.read(wearFleetProvider.notifier);
    switch (state) {
      case AppLifecycleState.resumed:
        _endOngoing();
        fleet.leaveBackground();
        unawaited(fleet.refresh());
      case AppLifecycleState.paused:
        final args = _ongoingArgs(ref.read(wearFleetProvider));
        if (args == null) {
          fleet.stopPolling();
        } else {
          unawaited(_startOngoing(fleet, args));
        }
      case _:
        break;
    }
  }

  Future<void> _startOngoing(
    WearFleetNotifier fleet,
    Map<String, Object?> args,
  ) async {
    fleet.pollInBackground();
    _ongoingSub?.close();
    final sub = ref.listenManual(wearFleetProvider, (_, next) {
      // A frame restored from the cache after a rebuild can be older than the
      // print, and would end it before the poll behind it lands.
      if (next.hasError || !next.hasValue || next.requireValue.stale) return;
      final args = _ongoingArgs(next);
      if (args == null) {
        _endOngoing();
        fleet.stopPolling();
      } else {
        unawaited(ref.read(wearOngoingProvider).show(args));
      }
    });
    _ongoingSub = sub;
    final shown = await ref.read(wearOngoingProvider).show(args);
    // Refused from the background: without the service nothing keeps the
    // process up, and a poll nobody sees only wakes the phone. Only this
    // pause's own session: a resume and another pause may have come since.
    if (!shown && mounted && _ongoingSub == sub) {
      _endOngoing();
      fleet.stopPolling();
    }
  }

  void _endOngoing() {
    _ongoingSub?.close();
    _ongoingSub = null;
    unawaited(ref.read(wearOngoingProvider).stop());
  }

  Map<String, Object?>? _ongoingArgs(AsyncValue<WearFleet> fleet) {
    final drawable = fleet.drawable;
    if (drawable == null) return null;
    return wearOngoingArgs(
      drawable,
      systemAppLocalizations(),
      DateTimeFormats.system(),
      clock.now(),
    );
  }

  /// Cold start: the phone may have pushed while the watch app was closed, so
  /// read the latest latched context and route it the same way a live push goes
  /// — unless a live push landed while it was being read.
  Future<void> _ingestPendingConfig() async {
    final config = await ref.read(watchConfigSyncProvider).latestPending();
    if (config != null && !_livePushSeen) await _routeConfig(config);
  }

  /// Decides what an incoming config is allowed to do on its own.
  ///
  /// Only a push naming the server already running is adopted silently — that
  /// one carries a refreshed secret for a server the user has already chosen.
  /// Anything else is a switch, so it is offered rather than applied: the phone
  /// pushes on every launch, and this app used to let those overwrite a watch
  /// that was working, with nothing on screen to say so.
  Future<void> _routeConfig(WatchConfig config) async {
    if (!mounted) return;
    // The colour is the phone's to set whichever server the config names.
    unawaited(ref.read(wearPhoneAccentProvider.notifier).set(config.accent));
    if (config.isSameServerAs(ref.read(serverProfileProvider))) {
      await _applyConfig(config);
      return;
    }
    ref.read(pendingWatchConfigProvider.notifier).offer(config);
  }

  Future<void> _applyConfig(WatchConfig config) async {
    try {
      await ref.read(pendingWatchConfigProvider.notifier).adopt(config);
    } catch (_) {
      // Nothing on screen to tell: this runs without anyone having asked for it.
      // A failed write leaves the profile as it was and the config on the Data
      // Layer latch, so the setup screen can offer it again.
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasProfile = ref.watch(
      serverProfileProvider.select((p) => p != null),
    );
    return MaterialApp(
      title: 'Bambuddy Watch',
      debugShowCheckedModeBanner: false,
      theme: wearTheme(ref.watch(wearColorSchemeProvider)),
      // Follow the watch's system language (same l10n set as the phone app).
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      // Above the navigator, so routes *and* dialogs read the same shape: the
      // round face is what every layout under here insets itself against.
      builder: (context, child) => WearShapeScope(child: child!),
      home: hasProfile ? const WearHome() : const WearSetupScreen(),
    );
  }
}
