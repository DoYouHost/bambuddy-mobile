import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/duration_format.dart';
import '../../core/models/queue_settings.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import '../../providers.dart';
import '../common/dash_async.dart';
import '../common/dash_snack.dart';
import '../common/state_views.dart';
import '../common/inline_note.dart';
import '../common/settings_rows.dart';
import '../common/system_insets.dart';
import 'queue_settings_providers.dart';

/// How the scheduler runs the queue, warms a printer before a job, and holds a
/// bed hot between two jobs that both need a warm chamber.
///
/// **These are the server's settings, not this phone's** — every user of the
/// server gets what is set here, which is why the screen says so at the top
/// rather than leaving it to be inferred from the title.
///
/// Every row is offered only when `GET /settings` answered its key. The
/// response always carries the full schema, defaulted, so a missing key is the
/// server predating the setting — and writing one it does not know would be
/// dropped in silence rather than refused (`extra="ignore"`), which is the one
/// failure a settings screen must never have.
class QueueSettingsScreen extends ConsumerWidget {
  const QueueSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // Null while the verdict is still being worked out. Unresolved is *not*
    // writable: defaulting to "yes" lit the controls for a second on a session
    // that would only ever get a 403 out of them, and the lock banner then
    // arrived on top of a tap the user had already made.
    final lock = ref.watch(queueSettingsLockProvider).valueOrNull;

    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: dashAppBar(context, title: l10n.queueSettingsTitle),
        // The settings are fetched once per session and shared with every
        // feature gate in the app, so a change made on the web has no other way
        // in — and a failed fetch degrades to an empty map, which without this
        // left the screen blank with nothing to press.
        body: RefreshIndicator(
          onRefresh: () async {
            // The repository too, not just the settings: it carries the latch
            // a 403 closed, and that latch is what greys the form. Without a
            // fresh one, a permission granted server-side after the refusal
            // could never be picked up — the controls that would have proved
            // it are the ones being greyed. `queueSettingsLockProvider`
            // watches the repository, so it rebuilds off this and needs no
            // invalidation of its own.
            ref.invalidate(serverSettingsRepositoryProvider);
            await ref.read(serverSettingsProvider.notifier).refresh();
          },
          child: dashAsync(
            context,
            ref.watch(queueSettingsProvider),
            onRetry: () => ref.invalidate(serverSettingsProvider),
            data: (settings) => settings.known.isEmpty
                ? EmptyStateView(
                    message: l10n.queueSettingsUnavailable,
                    icon: Icons.tune,
                  )
                : ListView(
                    padding: withSystemNavInset(
                      context,
                      const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    ),
                    children: [
                      if (_lockReason(l10n, lock) case final reason?) ...[
                        InlineNote(
                          reason,
                          icon: Icons.lock_outline,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                        ),
                        const SizedBox(height: 12),
                      ],
                      ..._sections(context, ref, settings, lock),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  /// Why the rows below cannot be touched, or null when they can — and null
  /// too while the verdict is pending, so a banner does not flash up and
  /// disappear on a session that turns out to be allowed.
  String? _lockReason(AppLocalizations l10n, QueueSettingsLock? lock) =>
      switch (lock) {
        null || QueueSettingsLock.none => null,
        QueueSettingsLock.apiKey => l10n.queueSettingsReadOnlyApiKey,
        QueueSettingsLock.permission => l10n.queueSettingsReadOnlyPermission,
      };

  List<Widget> _sections(
    BuildContext context,
    WidgetRef ref,
    QueueSettings settings,
    QueueSettingsLock? lock,
  ) {
    final l10n = AppLocalizations.of(context);
    final writable = lock == QueueSettingsLock.none;

    // Writing one setting: optimistic on screen, reverted with the reason if
    // the server refuses it.
    Future<void> write(QueueSetting setting, Object value) async {
      final messenger = ScaffoldMessenger.of(context);
      final outcome = await ref
          .read(queueSettingsProvider.notifier)
          .set(setting, value);
      if (outcome.messageFor(l10n) case final message?) {
        messenger.snack(message);
      }
    }

    bool has(QueueSetting setting) => settings.known.contains(setting);
    bool enabled(QueueSetting master) =>
        writable && (!has(master) || settings.flag(master));

    // A section whose master switch is off greys its dependants. The switch is
    // right above them, but "why is this grey" has two possible answers on this
    // screen — the master, or the whole form being read-only — so the section
    // says which one applies to it.
    //
    // [dependants] is what the note is actually about. An older server can
    // answer the master and none of the rows under it, and a note explaining
    // why rows that are not on screen are greyed explains nothing.
    Widget? mastered(
      QueueSetting master,
      String reason,
      List<QueueSetting> dependants,
    ) =>
        writable && has(master) && !settings.flag(master) && dependants.any(has)
        ? InlineNote(reason, icon: Icons.info_outline)
        : null;

    return [
      ..._section(l10n.queueSettingsQueueHeader, [
        if (has(QueueSetting.requirePlateClear))
          SettingsSwitchRow(
            tag: 'queue_settings.require_plate_clear',
            title: l10n.queueSettingsPlateClearTitle,
            subtitle: l10n.queueSettingsPlateClearDesc,
            value: settings.flag(QueueSetting.requirePlateClear),
            onChanged: writable
                ? (v) => write(QueueSetting.requirePlateClear, v)
                : null,
          ),
        if (has(QueueSetting.shortestFirst))
          SettingsSwitchRow(
            tag: 'queue_settings.shortest_first',
            title: l10n.queueSettingsShortestFirstTitle,
            subtitle: l10n.queueSettingsShortestFirstDesc,
            value: settings.flag(QueueSetting.shortestFirst),
            onChanged: writable
                ? (v) => write(QueueSetting.shortestFirst, v)
                : null,
          ),
        if (has(QueueSetting.maxConcurrentUploads))
          _slider(
            ref,
            QueueSetting.maxConcurrentUploads,
            settings,
            tag: 'queue_settings.max_uploads',
            label: l10n.queueSettingsMaxUploads(
              settings.number(QueueSetting.maxConcurrentUploads),
            ),
            subtitle: l10n.queueSettingsMaxUploadsDesc,
            bubble: '${settings.number(QueueSetting.maxConcurrentUploads)}',
            enabled: writable,
            onChangeEnd: write,
          ),
      ]),
      ..._section(
        l10n.queueSettingsPreheatHeader,
        [
          if (has(QueueSetting.preheatEnabled))
            SettingsSwitchRow(
              tag: 'queue_settings.preheat_enabled',
              title: l10n.queueSettingsPreheatTitle,
              subtitle: l10n.queueSettingsPreheatDesc,
              value: settings.flag(QueueSetting.preheatEnabled),
              onChanged: writable
                  ? (v) => write(QueueSetting.preheatEnabled, v)
                  : null,
            ),
          if (has(QueueSetting.preheatMaxWaitSeconds))
            _durationSlider(
              ref,
              QueueSetting.preheatMaxWaitSeconds,
              settings,
              l10n,
              tag: 'queue_settings.preheat_max_wait',
              label: l10n.queueSettingsPreheatMaxWait,
              subtitle: l10n.queueSettingsPreheatMaxWaitDesc,
              enabled: enabled(QueueSetting.preheatEnabled),
              onChangeEnd: write,
            ),
          if (has(QueueSetting.preheatSoakSeconds))
            _durationSlider(
              ref,
              QueueSetting.preheatSoakSeconds,
              settings,
              l10n,
              tag: 'queue_settings.preheat_soak',
              label: l10n.queueSettingsPreheatSoak,
              subtitle: l10n.queueSettingsPreheatSoakDesc,
              zeroLabel: l10n.queueSettingsNoSoak,
              enabled: enabled(QueueSetting.preheatEnabled),
              onChangeEnd: write,
            ),
        ],
        note: mastered(
          QueueSetting.preheatEnabled,
          l10n.queueSettingsPreheatOffNote,
          const [
            QueueSetting.preheatMaxWaitSeconds,
            QueueSetting.preheatSoakSeconds,
          ],
        ),
      ),
      ..._section(
        l10n.queueSettingsKeepWarmHeader,
        [
          if (has(QueueSetting.keepBedWarm))
            SettingsSwitchRow(
              tag: 'queue_settings.keep_bed_warm',
              title: l10n.queueSettingsKeepWarmTitle,
              subtitle: l10n.queueSettingsKeepWarmDesc,
              value: settings.flag(QueueSetting.keepBedWarm),
              onChanged: writable
                  ? (v) => write(QueueSetting.keepBedWarm, v)
                  : null,
            ),
          if (has(QueueSetting.keepWarmBedTemp))
            _slider(
              ref,
              QueueSetting.keepWarmBedTemp,
              settings,
              tag: 'queue_settings.keep_warm_temp',
              label: l10n.queueSettingsKeepWarmTemp(
                settings.number(QueueSetting.keepWarmBedTemp),
              ),
              subtitle: l10n.queueSettingsKeepWarmTempDesc,
              bubble: '${settings.number(QueueSetting.keepWarmBedTemp)} °C',
              // Not gated on the keep-warm switch: the same value is what
              // preheat falls back to when a chamber-heated job's slicer
              // metadata carries no bed temperature at all
              // (`services/print_scheduler.py`), so it still does something
              // with keep-warm off.
              enabled: writable,
              onChangeEnd: write,
            ),
          if (has(QueueSetting.keepWarmMaxMinutes))
            _slider(
              ref,
              QueueSetting.keepWarmMaxMinutes,
              settings,
              tag: 'queue_settings.keep_warm_max_minutes',
              label: l10n.queueSettingsKeepWarmMax(
                formatMinutes(
                  l10n,
                  settings.number(QueueSetting.keepWarmMaxMinutes),
                ),
              ),
              subtitle: l10n.queueSettingsKeepWarmMaxDesc,
              bubble: formatMinutes(
                l10n,
                settings.number(QueueSetting.keepWarmMaxMinutes),
              ),
              step: 5,
              enabled: enabled(QueueSetting.keepBedWarm),
              onChangeEnd: write,
            ),
        ],
        // Only about the bed temperature, which is the row that keeps working
        // with keep-warm off — so the note goes when that row does, whatever
        // else the section still shows.
        note: mastered(
          QueueSetting.keepBedWarm,
          l10n.queueSettingsKeepWarmOffNote,
          const [QueueSetting.keepWarmBedTemp],
        ),
      ),
    ];
  }

  /// A header and its card, or nothing at all — a server too old for every
  /// setting in the group has no reason to show the group's name.
  List<Widget> _section(String header, List<Widget> rows, {Widget? note}) =>
      rows.isEmpty
      ? const []
      : [
          SettingsSectionHeader(header),
          SettingsCard(rows: rows),
          ?note,
          const SizedBox(height: 20),
        ];

  /// A slider over a span the server keeps in seconds.
  ///
  /// **Minute steps.** At the 30-second step this had, every other stop read
  /// the same as the one before it — `formatSeconds` drops the leftover
  /// seconds — so the label sat still while the value moved, and the number
  /// reaching the server was not the one on screen. The label still spells a
  /// remainder out ([formatSecondsExact]), because a value set on the web can
  /// carry one and the row must not round it away in silence.
  ///
  /// The first touch then snaps such a value onto the minute grid — 930 s
  /// reads "15min 30s" until it is dragged and "15min" or "16min" after.
  /// Deliberate: the grid is what the control offers, the label never lies
  /// about where the value actually is, and the alternative — a grid offset by
  /// whatever odd number the row happened to hold — would make a round 15min
  /// unreachable from this screen.
  Widget _durationSlider(
    WidgetRef ref,
    QueueSetting setting,
    QueueSettings settings,
    AppLocalizations l10n, {
    required String tag,
    required String Function(String) label,
    required String subtitle,
    required bool enabled,
    required Future<void> Function(QueueSetting, Object) onChangeEnd,
    String? zeroLabel,
  }) {
    final seconds = settings.number(setting);
    final spelled = seconds == 0 && zeroLabel != null
        ? zeroLabel
        : formatSecondsExact(l10n, seconds);
    return _slider(
      ref,
      setting,
      settings,
      tag: tag,
      label: label(spelled),
      subtitle: subtitle,
      bubble: spelled,
      step: 60,
      enabled: enabled,
      onChangeEnd: onChangeEnd,
    );
  }

  Widget _slider(
    WidgetRef ref,
    QueueSetting setting,
    QueueSettings settings, {
    required String tag,
    required String label,
    required String subtitle,
    required bool enabled,
    required Future<void> Function(QueueSetting, Object) onChangeEnd,
    String? bubble,
    int step = 1,
  }) => SettingsSlider(
    tag: tag,
    label: label,
    subtitle: subtitle,
    bubble: bubble,
    value: settings.number(setting),
    min: setting.min!,
    max: setting.max!,
    step: step,
    enabled: enabled,
    // Dragging redraws the label from the notifier's own state, so the number
    // above the thumb follows the finger; only letting go writes.
    onChanged: (v) =>
        ref.read(queueSettingsProvider.notifier).preview(setting, v),
    onChangeEnd: (v) => onChangeEnd(setting, v),
  );
}
