import 'dart:async';

import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:app_update/app_update.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/diagnostics/diagnostics_wiring.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../dashboard/widgets/connection_banner.dart';

/// The Google Play update the app offers beside the maintainers' announcements.
/// It never touches the server. `unread` is kept on the phone, per version.
typedef AppUpdate = ({PlayUpdateState play, bool unread});

extension AppUpdateOffer on AppUpdate {
  bool get offered => play.phase != PlayUpdatePhase.none;
}

/// SharedPreferences key of the newest `versionCode` whose entry was opened.
const appUpdateSeenKey = 'app_update_seen_version';

final appUpdateProvider = NotifierProvider<AppUpdateNotifier, AppUpdate>(
  AppUpdateNotifier.new,
);

class AppUpdateNotifier extends Notifier<AppUpdate> {
  late PlayUpdate _play;

  @override
  AppUpdate build() {
    final play = _play = PlayUpdate(
      // Play's own code and text ("TASK_FAILURE", "-10: …"), nothing of ours.
      onError: (e) => DiagnosticRecorder.active?.add(
        LogSource.app,
        'play_update_error',
        fields: {'code': e.code, 'message': e.message},
      ),
      onAnswer: PlayCheckProbe.answered,
    );
    play.addListener(_publish);
    // Play is asked again on every resume: that is how a download finished in
    // the background, or by an earlier process, is found.
    final lifecycle = AppLifecycleListener(
      onResume: () => unawaited(play.check()),
    );
    ref.onDispose(() {
      lifecycle.dispose();
      play.dispose();
    });
    unawaited(play.check());
    return _snapshot(play.value);
  }

  void _publish() {
    final play = _play.value;
    DiagnosticRecorder.active?.add(
      LogSource.app,
      'play_update',
      fields: {'phase': play.phase.name, 'version_code': play.versionCode},
    );
    state = _snapshot(play);
  }

  // Preferences are read only once there is an offer, which only a Play
  // install ever has.
  AppUpdate _snapshot(PlayUpdateState play) => (
    play: play,
    unread:
        play.phase != PlayUpdatePhase.none &&
        ref.read(sharedPreferencesProvider).getInt(appUpdateSeenKey) !=
            play.versionCode,
  );

  void markRead() {
    final code = state.play.versionCode;
    if (!state.unread || code == null) return;
    unawaited(
      ref.read(sharedPreferencesProvider).setInt(appUpdateSeenKey, code),
    );
    state = (play: state.play, unread: false);
  }

  Future<void> download() {
    markRead();
    return _play.download();
  }

  void install() => _play.install();
}

/// The one thing about an update the dashboard shows: it is downloaded and
/// waits for a restart, which nobody should have to look for in the inbox.
class AppUpdateReadyBanner extends ConsumerWidget {
  const AppUpdateReadyBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(appUpdateProvider).play.phase != PlayUpdatePhase.ready) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    return ConnectionBanner(
      message: l10n.appUpdateReady,
      tone: BannerTone.info,
      icon: Icons.system_update,
      action: TextButton(
        onPressed: ref.read(appUpdateProvider.notifier).install,
        child: Text(l10n.appUpdateRestart),
      ).tagged('dashboard.app_update_restart'),
    );
  }
}
