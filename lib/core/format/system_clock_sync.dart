import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../notifications/background_monitor.dart';
import '../notifications/background_sync.dart';
import '../platform/platform_query.dart';
import '../settings/settings_repository.dart';
import 'datetime_format.dart';

/// Asks Android whether the user reads a 24-hour clock, through [MainActivity]'s
/// `clock` channel (`DateFormat.is24HourFormat`).
///
/// Flutter's own answer goes stale: the engine pushes the user settings when the
/// view attaches and never again, so flipping the switch in Android's settings
/// and coming back leaves `MediaQuery` on the old value until the process is
/// killed — measured on device, with the ETA still in AM/PM after the phone had
/// been put on a 24-hour clock.
///
/// Null means nobody answered — another platform, a test, a host without the
/// channel — and the caller falls back to what the widget tree says.
class SystemClockQuery {
  const SystemClockQuery({this.platform = _platform});

  static const _platform = PlatformQuery(
    MethodChannel('page.codeberg.morganmlgman.bambuddy/clock'),
  );

  /// Who to ask. Injectable so a test can answer for either clock.
  final PlatformQuery platform;

  Future<bool?> read() =>
      platform.ask<bool?>('is24HourFormat', fallback: null);
}

/// Writes the clock down for the isolates that cannot read it, then tells a
/// service that is already running to pick it up.
///
/// In that order, and awaited: the service reloads preferences the moment it is
/// asked, so a ping sent beside the write can read the clock the app has just
/// replaced. A service that is not running yet needs no ping — it reads the same
/// value in its own start-up.
Future<void> publishSystemClock(
  bool use24Hour, {
  required SettingsRepository settings,
  required BackgroundMonitor monitor,
}) async {
  await settings.saveUse24HourClock(use24Hour);
  if (await monitor.isRunning()) monitor.sync(BackgroundSync.clock);
}

/// Keeps the 12/24-hour clock true for everything below it, and for everything
/// that cannot ask at all.
///
/// Two audiences. Below it, the metric is republished into [MediaQuery], so a
/// switch flipped while the app was running reaches every screen on the next
/// resume instead of on the next cold start. Outside the tree — the foreground
/// service and the home-widget publisher, whose engine is never sent the user
/// settings — it goes into [DateTimeFormats.rememberSystemClock] and, through
/// [onChanged], into preferences, the only channel that reaches a service
/// isolate started after the app is gone.
class SystemClockSync extends StatefulWidget {
  const SystemClockSync({
    super.key,
    required this.onChanged,
    required this.child,
    this.query = const SystemClockQuery(),
  });

  /// Called with the current value on the first frame and on every change —
  /// persist it here.
  final void Function(bool use24Hour) onChanged;

  /// How the platform is asked. Overridden in tests; there is one implementation.
  final SystemClockQuery query;

  final Widget child;

  @override
  State<SystemClockSync> createState() => _SystemClockSyncState();
}

class _SystemClockSyncState extends State<SystemClockSync>
    with WidgetsBindingObserver {
  /// What the platform answered, null until it has or where it cannot.
  bool? _platform;

  bool? _published;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_ask());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The switch is flipped in Android's settings, which means leaving the app —
  /// so coming back is the moment the answer can have changed.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_ask());
  }

  Future<void> _ask() async {
    final answer = await widget.query.read();
    if (!mounted || answer == _platform) return;
    setState(() => _platform = answer);
    _publish();
  }

  /// Reading the metric here is what subscribes this element to it, so a value
  /// the engine does push still arrives on its own.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _publish();
  }

  bool get _use24Hour =>
      _platform ?? MediaQuery.alwaysUse24HourFormatOf(context);

  void _publish() {
    final use24Hour = _use24Hour;
    if (use24Hour == _published) return;
    _published = use24Hour;
    DateTimeFormats.rememberSystemClock(use24Hour);
    widget.onChanged(use24Hour);
  }

  @override
  Widget build(BuildContext context) => MediaQuery(
        // The whole data, not just the flag: this replaces the app's metrics for
        // everything below, and dropping the rest would take the text scale and
        // the insets with it.
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: _use24Hour),
        child: widget.child,
      );
}
