import 'dart:async';

import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../common/settings_rows.dart';
import 'wall_providers.dart';

const _landscape = [
  DeviceOrientation.landscapeLeft,
  DeviceOrientation.landscapeRight,
];

/// Always-on farm view for a phone or tablet on a stand (docs/tv-flavor.md
/// §13): landscape, no system bars, and the screen held on while the
/// "keep screen awake" setting says so.
///
/// Pushed over the dashboard, never swapped in for it: the dashboard owns the
/// foreground service and the token refreshers, which must keep running under
/// the wall.
class WallScreen extends ConsumerStatefulWidget {
  const WallScreen({super.key});

  /// How long the controls stay up after a tap.
  static const controlsTimeout = Duration(seconds: 5);

  @override
  ConsumerState<WallScreen> createState() => _WallScreenState();
}

class _WallScreenState extends ConsumerState<WallScreen> {
  // Read once here: `dispose` must still reach it, and `ref` is gone by then.
  late final ScreenAwake _awake;
  bool _controls = false;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    _awake = ref.read(screenAwakeProvider);
    unawaited(SystemChrome.setPreferredOrientations(_landscape));
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
    unawaited(_awake.set(ref.read(wallKeepAwakeProvider)));
  }

  @override
  void dispose() {
    _hide?.cancel();
    // Every way out lands here — Back, the exit button, and `/setup` replacing
    // the whole stack when the session expires — so the rest of the app gets
    // its free rotation, its bars and its screen timeout back on each of them.
    // The app sets no orientation of its own, so "restore" is the empty list.
    unawaited(SystemChrome.setPreferredOrientations(const []));
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    unawaited(_awake.set(false));
    super.dispose();
  }

  void _showControls() {
    _hide?.cancel();
    setState(() => _controls = true);
    _hide = Timer(WallScreen.controlsTimeout, () {
      if (mounted) setState(() => _controls = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    ref.listen<bool>(wallKeepAwakeProvider, (_, on) => _awake.set(on));

    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Positioned.fill(
              child: logTag(
                'wall.surface',
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _showControls,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.view_quilt_outlined,
                          size: 48,
                          color: t.textSecondary,
                        ),
                        const SizedBox(height: 12),
                        Text(l10n.wallModeTitle, style: t.displayLg),
                        const SizedBox(height: 8),
                        Text(
                          l10n.wallModeTapHint,
                          style: t.body.copyWith(color: t.textSecondary),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_controls)
              Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: _Controls(onInteract: _showControls),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Controls extends ConsumerWidget {
  const _Controls({required this.onInteract});

  /// Keeps the controls up while the user is working them.
  final VoidCallback onInteract;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    return SettingsCard(
      rows: [
        Row(
          children: [
            Expanded(child: Text(l10n.wallModeTitle, style: t.titleMd)),
            logTag(
              'wall.exit',
              IconButton(
                tooltip: l10n.wallModeExit,
                color: t.textPrimary,
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          ],
        ),
        SettingsSwitchRow(
          tag: 'wall.keep_awake',
          title: l10n.wallKeepAwakeTitle,
          subtitle: l10n.wallKeepAwakeDesc,
          value: ref.watch(wallKeepAwakeProvider),
          onChanged: (on) {
            onInteract();
            ref.read(wallKeepAwakeProvider.notifier).set(on);
          },
        ),
      ],
    );
  }
}
