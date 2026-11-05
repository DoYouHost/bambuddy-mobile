import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/settings/settings_repository.dart';
import '../../core/theme/app_brand.dart';
import '../../core/theme/appearance_providers.dart';
import '../../core/theme/dash_theme.dart';

/// The alarm screen's own channel to `AlarmActivity`: `content` asks what to show,
/// `stop` stops every alarm, and the activity pushes `show` when another alarm
/// reaches the screen already up.
const alarmScreenChannel = MethodChannel(
  'page.codeberg.morganmlgman.bambuddy/alarm_screen',
);

/// One alarm still ringing. Strings arrive localized from the ring; [printer]
/// is empty for the test alarm.
typedef AlarmEntry = ({String title, String body, String printer});

/// What the screen shows: every alarm still ringing, newest first.
typedef AlarmContent = ({List<AlarmEntry> alarms, String stop});

String _text(Map raw, String key) => raw[key] as String? ?? '';

AlarmContent? _contentFrom(Object? raw) => raw is Map
    ? (
        alarms: [
          if (raw['alarms'] case final List list)
            for (final a in list)
              if (a is Map)
                (
                  title: _text(a, 'title'),
                  body: _text(a, 'body'),
                  printer: _text(a, 'printer'),
                ),
        ],
        stop: _text(raw, 'stop'),
      )
    : null;

/// Runs the alarm screen in `AlarmActivity`'s own engine (#61). Nothing else of
/// the app is in this tree: the screen shows over a locked phone, and the app
/// must not be one tap away from it there. Always dark — it is mostly seen at
/// night — in the accent the user chose.
Future<void> runAlarmScreen() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final accent = SettingsRepository(prefs).loadAppearancePrefs().accent;
  final brand = resolveBrand(accent, await readSystemSchemes());
  final content = _contentFrom(
    await alarmScreenChannel.invokeMethod<Object?>('content'),
  );
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildDashThemeData(Brightness.dark, brand: brand),
      home: AlarmScreen(initial: content),
    ),
  );
}

class AlarmScreen extends StatefulWidget {
  const AlarmScreen({super.key, required this.initial});

  final AlarmContent? initial;

  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends State<AlarmScreen> {
  late AlarmContent? _content = widget.initial;

  @override
  void initState() {
    super.initState();
    alarmScreenChannel.setMethodCallHandler((call) async {
      if (call.method == 'show') {
        setState(() => _content = _contentFrom(call.arguments));
      }
    });
  }

  @override
  void dispose() {
    alarmScreenChannel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final content = _content;
    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, box) => SingleChildScrollView(
              padding: const EdgeInsets.all(DashSpace.xl),
              // At least the screen's height, so the content sits centred until
              // a large font makes it scroll.
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: box.maxHeight - 2 * DashSpace.xl,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(DashRadius.xl),
                        child: Image.asset(
                          'assets/icon/app_logo.png',
                          width: DashSize.d64,
                          height: DashSize.d64,
                        ),
                      ),
                    ),
                    const SizedBox(height: DashSpace.xl),
                    Icon(Icons.alarm, size: DashIcon.xl, color: t.accent),
                    for (final alarm in content?.alarms ?? const <AlarmEntry>[])
                      _AlarmEntryView(alarm),
                    const SizedBox(height: DashSpace.xxl),
                    FilledButton(
                      onPressed: () =>
                          alarmScreenChannel.invokeMethod<void>('stop'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(DashSize.d64),
                      ),
                      child: Text(content?.stop ?? ''),
                    ).tagged('alarm.stop'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One alarm: which printer, what happened, the detail.
class _AlarmEntryView extends StatelessWidget {
  const _AlarmEntryView(this.alarm);

  final AlarmEntry alarm;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: DashSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (alarm.printer.isNotEmpty)
            Text(
              alarm.printer,
              textAlign: TextAlign.center,
              style: t.titleSm.copyWith(color: t.accent),
            ),
          Text(alarm.title, textAlign: TextAlign.center, style: t.titleLg),
          const SizedBox(height: DashSpace.xs),
          Text(alarm.body, textAlign: TextAlign.center, style: t.body),
        ],
      ),
    );
  }
}
