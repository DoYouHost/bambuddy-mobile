import 'package:app_util/app_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/dash_theme.dart';
import '../../core/settings/server_profile.dart';
import '../../core/watch/watch_config_sync.dart';
import '../../features/setup/providers.dart';
import '../../features/setup/setup_error_text.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../wear_action.dart';
import '../wear_theme.dart';
import '../wear_providers.dart';
import '../widgets/wear_header.dart';
import '../widgets/wear_screen.dart';
import '../widgets/wear_scroll_view.dart';
import '../widgets/wear_spinner.dart';
import '../widgets/wear_toast.dart';

/// The phone half of setup, through `WearPhoneApp.kt` in the wear source set.
const _phoneApp = PlatformQuery(
  MethodChannel('page.codeberg.morganmlgman.bambuddy/wear_phone_app'),
);

/// Without Play services a Data Layer call never answers at all.
const _phoneTimeout = Duration(seconds: 5);

/// Watch setup: the server and the credentials come from the phone, or the demo
/// starts with one tap. Nothing is typed here — Play's WO-P6 forbids a username
/// and password entered on the watch, and an API key or a URL is the same chore.
class WearSetupScreen extends ConsumerStatefulWidget {
  const WearSetupScreen({super.key});

  @override
  ConsumerState<WearSetupScreen> createState() => _WearSetupScreenState();
}

class _WearSetupScreenState extends ConsumerState<WearSetupScreen>
    with WearAction, WidgetsBindingObserver {
  /// The last check found nothing latched — worth saying out loud, or the button
  /// looks broken.
  bool _phoneEmpty = false;

  /// The last check failed outright, as opposed to coming back empty.
  Object? _phoneError;

  /// Whether the paired phone has the app; null where no phone is connected or
  /// the watch cannot tell, which offers nothing to install. Asked again on every
  /// check and on coming back, since the answer is what the user goes off to
  /// change — and an older phone app advertises nothing, so a false here may be
  /// wrong, which is why the prompt is a question.
  bool? _phoneHasApp;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _askPhoneApp();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _askPhoneApp();
  }

  Future<void> _askPhoneApp() async {
    // Bounded on the native side (`WearPhoneApp.kt`), which answers null.
    final installed = await _phoneApp.ask<bool?>('installed', fallback: null);
    if (mounted) setState(() => _phoneHasApp = installed);
  }

  /// [below] is a context under the [WearScreen] this state builds, which is
  /// where the toast lives.
  Future<void> _installOnPhone(BuildContext below) => run(() async {
    final opened = await _phoneApp
        .ask<bool>('openStore', fallback: false)
        .timeout(_phoneTimeout, onTimeout: () => false);
    if (!below.mounted) return;
    final l10n = AppLocalizations.of(below);
    wearToast(
      below,
      opened ? l10n.wearPhoneAppOpened : l10n.wearPhoneAppOpenFailed,
      tone: opened ? WearToastTone.success : WearToastTone.failure,
    );
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final offer = ref.watch(pendingWatchConfigProvider);

    return WearScreen(
      child: Builder(
        builder: (below) => WearScrollView(
          curved: true,
          // Every branch below is a step of its own; naming it here is what
          // brings the scroll back to the top when the screen swaps.
          resetKey: offer != null ? 'offer' : 'handoff',
          children: [
            const WearHeader('Bambuddy'),
            const SizedBox(height: DashSpace.md),
            if (offer case final offer?)
              ..._offerSection(l10n, offer)
            else
              ..._phoneHandoffSection(l10n, below),
          ],
        ),
      ),
    );
  }

  /// What the phone sent, shown before it is used rather than after.
  ///
  /// The push carries credentials for a server the watch has never talked to, so
  /// it is worth a look: a phone that switched servers used to reconfigure the
  /// watch silently, and nothing on the watch said which server it was on.
  List<Widget> _offerSection(AppLocalizations l10n, WatchConfig offer) => [
    Text(l10n.wearFromPhone, textAlign: TextAlign.center, style: WearText.body),
    const SizedBox(height: DashSpace.xs),
    Text(
      offer.profile.displayName,
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: WearText.section,
    ),
    const SizedBox(height: DashSpace.xs),
    Text(
      switch (offer.profile.authMode) {
        AuthMode.apiKey => l10n.wearAuthKey,
        AuthMode.jwt => l10n.wearAuthLogin,
        AuthMode.none => l10n.wearAuthNone,
      },
      textAlign: TextAlign.center,
      style: WearText.fine,
    ),
    if (_phoneError != null) ...[
      const SizedBox(height: DashSpace.sm),
      Text(
        _errorText(l10n, _phoneError!),
        textAlign: TextAlign.center,
        style: wearErrorStyle(context),
      ),
    ],
    const SizedBox(height: DashSpace.md),
    if (busy)
      wearSpinner
    else
      FilledButton(
        onPressed: () => _useOffer(offer),
        child: Text(l10n.wearFromPhoneUse),
      ),
    TextButton(
      onPressed: busy
          ? null
          : () => ref.read(pendingWatchConfigProvider.notifier).dismiss(),
      child: Text(l10n.wearFromPhoneLater),
    ),
  ];

  /// Adopt the offered config. The failure has to stay on screen: it is what
  /// stands between the user and a working watch, so a message that times out
  /// would be no message at all.
  Future<void> _useOffer(WatchConfig offer) {
    setState(() => _phoneError = null);
    return run(
      () => ref.read(pendingWatchConfigProvider.notifier).adopt(offer),
      onError: (error) => setState(() => _phoneError = error),
    );
  }

  /// The path almost everybody should take: the phone already knows the server
  /// and the credentials, and pushes both over the Data Layer.
  List<Widget> _phoneHandoffSection(
    AppLocalizations l10n,
    BuildContext below,
  ) => [
    Text(
      l10n.wearSetupPhoneTitle,
      textAlign: TextAlign.center,
      style: WearText.section,
    ),
    const SizedBox(height: DashSpace.sm),
    Text(
      l10n.wearSetupPhoneBody,
      textAlign: TextAlign.center,
      style: WearText.small,
    ),
    if (_phoneEmpty || _phoneError != null) ...[
      const SizedBox(height: DashSpace.sm),
      Text(
        switch (_phoneError) {
          final error? => _errorText(l10n, error),
          null => l10n.wearSetupPhoneEmpty,
        },
        textAlign: TextAlign.center,
        style: wearErrorStyle(context),
      ),
    ],
    const SizedBox(height: DashSpace.md),
    if (busy)
      wearSpinner
    else
      FilledButton(
        onPressed: _checkPhone,
        child: Text(l10n.wearSetupPhoneCheck),
      ),
    if (_phoneHasApp == false) ...[
      const SizedBox(height: DashSpace.sm),
      Text(
        l10n.wearPhoneAppMissing,
        textAlign: TextAlign.center,
        style: WearText.body,
      ),
      const SizedBox(height: DashSpace.xs),
      FilledButton(
        onPressed: busy ? null : () => _installOnPhone(below),
        child: Text(l10n.wearPhoneAppInstall),
      ),
    ],
    TextButton(
      onPressed: busy ? null : _startDemo,
      child: Text(l10n.wearSetupDemo),
    ),
  ];

  /// Straight into demo mode.
  ///
  /// The sequence itself belongs to the shared controller (`enterDemo`), so the
  /// watch knows neither the address nor the credentials. The one way it fails
  /// is the profile write throwing — the same secure-storage failure
  /// [_useOffer] already shows. On a screen whose only other route needs the
  /// phone, a demo button that just puts itself back is a dead end with no
  /// explanation.
  Future<void> _startDemo() {
    setState(() => _phoneError = null);
    return run(
      () => ref.read(setupControllerProvider.notifier).enterDemo(),
      onError: (error) => setState(() => _phoneError = error),
    );
  }

  /// Look for what the phone last latched and *offer* it. A live push is picked
  /// up by `WearApp` on its own; this button is for the config that arrived
  /// while the watch app was closed, and for the user who wants to see
  /// something happen.
  Future<void> _checkPhone() {
    _askPhoneApp();
    setState(() {
      _phoneEmpty = false;
      _phoneError = null;
    });
    return run(() async {
      // Bounded on purpose: the Data Layer call never answers at all where
      // Google Play services are missing, and the run guard covers a throw,
      // not a call that simply never returns. Coming back empty at least
      // gives the button back.
      final found = await ref
          .read(watchConfigSyncProvider)
          .latestPending()
          .timeout(_phoneTimeout, onTimeout: () => null);
      if (!mounted) return;
      // Empty is an outcome, not a failure — hence a field of its own rather
      // than an error.
      setState(() => _phoneEmpty = found == null);
      if (found != null) {
        ref.read(pendingWatchConfigProvider.notifier).offer(found);
      }
    }, onError: (error) => setState(() => _phoneError = error));
  }
}

/// Localized via the shared setup mapper; anything unexpected stays short.
///
/// The mapping is what differs between the two watch screens that show errors —
/// this one speaks setup, the control screen speaks printer commands — so only
/// the look and the budget come from [wearShortText].
String _errorText(AppLocalizations l10n, Object error) =>
    wearShortText(setupErrorText(l10n, error), max: wearErrorMaxChars);
