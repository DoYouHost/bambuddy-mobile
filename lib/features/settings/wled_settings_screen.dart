import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/models/printer.dart';
import '../../core/models/wled_config.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common/api_failure_snack.dart';
import '../common/dash_async.dart';

/// The printers a mapping is chosen for; their rows carry the stored mapping.
final _wledPrintersProvider = FutureProvider.autoDispose<List<Printer>>(
  (ref) => ref.watch(printersRepositoryProvider).fetchPrinters(),
);

/// The finished-to-idle delay as typed: empty is 0 (off), anything but a whole
/// number in 0..86400 is null.
int? parseFinishedTimeout(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return 0;
  final value = int.tryParse(trimmed);
  if (value == null ||
      value < 0 ||
      value > WledConfig.maxFinishedTimeoutSeconds) {
    return null;
  }
  return value;
}

enum _Reach { unknown, online, offline }

/// WLED presets per printer state (server #1528), the web's Settings → WLED.
///
/// The server does the switching; this only edits the mapping it keeps on the
/// printer row. Presets are WLED's own, read through the server, which is also
/// the one that has to reach WLED, so every test runs from there.
///
/// A draft is kept per printer until it is saved, as on the web, so switching
/// printers to compare does not lose an edit. Every answer about WLED belongs
/// to the printer and URL it was asked for: [_context] moves on when either
/// changes, and an older answer is dropped.
class WledSettingsScreen extends ConsumerStatefulWidget {
  const WledSettingsScreen({super.key});

  @override
  ConsumerState<WledSettingsScreen> createState() => _WledSettingsState();
}

class _WledSettingsState extends ConsumerState<WledSettingsScreen> {
  final _url = TextEditingController();
  final _timeout = TextEditingController();

  int? _printerId;
  final _drafts = <int, WledConfig>{};

  /// What a save returned, newer than the printer row the list was read with.
  final _saved = <int, WledConfig?>{};

  int _context = 0;
  List<WledPreset>? _presets;
  _Reach _presetsReach = _Reach.unknown;
  _Reach _connection = _Reach.unknown;
  WledConnectionInfo? _info;
  String? _urlRefusal;
  bool _saving = false;
  bool _loadingPresets = false;
  bool _testingConnection = false;
  bool _testingPreset = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual(_wledPrintersProvider, (_, next) {
      final printers = next.value;
      if (printers == null || printers.isEmpty) return;
      if (printers.none((p) => p.id == _printerId)) _select(printers.first);
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _url.dispose();
    _timeout.dispose();
    super.dispose();
  }

  WledConfig _stored(Printer printer) => _saved.containsKey(printer.id)
      ? _saved[printer.id] ?? const WledConfig()
      : printer.wledConfig ?? const WledConfig();

  WledConfig _config(Printer printer) =>
      _drafts[printer.id] ?? _stored(printer);

  void _edit(Printer printer, WledConfig next) =>
      setState(() => _drafts[printer.id] = next);

  /// Moves on to a new printer or URL: what WLED said, and the requests still
  /// out about it, belonged to the old one. Their answers are dropped, so their
  /// busy flags are lowered here rather than by them.
  void _forgetWled() {
    _context++;
    _presets = null;
    _presetsReach = _Reach.unknown;
    _connection = _Reach.unknown;
    _info = null;
    _urlRefusal = null;
    _loadingPresets = false;
    _testingConnection = false;
    _testingPreset = false;
  }

  void _select(Printer printer) {
    final config = _config(printer);
    setState(() {
      _printerId = printer.id;
      _forgetWled();
      _url.text = config.baseUrl ?? '';
      _timeout.text = '${config.finishedTimeoutSeconds ?? 0}';
    });
    // As on the web: a saved, enabled mapping shows its preset names at once.
    // After the frame, since the first selection can come from `initState`,
    // where the request's context lookups are not allowed yet.
    final stored = _stored(printer);
    final url = stored.baseUrl;
    if (!stored.enabled || url == null || url != config.baseUrl) return;
    final selected = _context;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && selected == _context) _loadPresets(printer, url);
    });
  }

  void _urlChanged(Printer printer, String text) {
    final config = _config(printer);
    setState(_forgetWled);
    _edit(printer, config.copyWith(baseUrl: () => text.trim()));
  }

  /// Runs one request about WLED for [printer] at [url]. A 422 is the server
  /// refusing the URL and is said under the field; a 502 is WLED not
  /// answering, handed to [onOffline]. An answer that arrives after the printer
  /// or the URL changed is dropped.
  Future<void> _ask<T>(
    Printer printer,
    String url, {
    required String action,
    required Future<T> Function() request,
    required void Function(T answer) onAnswer,
    required void Function() onOffline,
    required void Function(bool busy) busy,
  }) async {
    final asked = _context;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    bool current() => mounted && asked == _context;
    setState(() => busy(true));
    try {
      final answer = await request();
      if (current()) setState(() => onAnswer(answer));
    } on ApiException catch (e) {
      if (!current()) return;
      if (e.statusCode == 422 && e.detail != null) {
        recordActionFailure(e, action: action, shown: true);
        setState(() => _urlRefusal = l10n.wledRefused(e.detail!));
      } else if (e.statusCode == 502) {
        setState(onOffline);
      } else {
        showApiFailure(messenger, e, l10n, action: action);
      }
    } on AppApiException catch (e) {
      showApiFailure(current() ? messenger : null, e, l10n, action: action);
    } finally {
      if (current()) setState(() => busy(false));
    }
  }

  void _loadPresets(Printer printer, String url) => _ask(
    printer,
    url,
    action: 'wled.load_presets',
    request: () =>
        ref.read(printersRepositoryProvider).fetchWledPresets(printer.id, url),
    onAnswer: (presets) {
      _presets = presets;
      _presetsReach = _Reach.online;
    },
    onOffline: () => _presetsReach = _Reach.offline,
    busy: (b) => _loadingPresets = b,
  );

  void _testConnection(Printer printer, String url) => _ask(
    printer,
    url,
    action: 'wled.test_connection',
    request: () => ref
        .read(printersRepositoryProvider)
        .testWledConnection(printer.id, url),
    onAnswer: (info) {
      _info = info;
      _connection = _Reach.online;
    },
    onOffline: () => _connection = _Reach.offline,
    busy: (b) => _testingConnection = b,
  );

  void _testPreset(Printer printer, String url, int presetId) {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    _ask(
      printer,
      url,
      action: 'wled.test_preset',
      request: () => ref
          .read(printersRepositoryProvider)
          .testWledPreset(printer.id, url, presetId),
      onAnswer: (_) => messenger.snack(l10n.wledPresetTested),
      onOffline: () => messenger.snack(l10n.wledPresetTestFailed),
      busy: (b) => _testingPreset = b,
    );
  }

  Future<void> _save(Printer printer, WledConfig config) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final asked = _context;
    // What the web checks before it reports a success: the same printer and
    // URL on screen, and nothing edited since. A failure is said while the
    // printer is still on screen, which the web does not: a draft that stays
    // unsaved owes the user the reason, and a refused URL still in the field
    // gets it underneath.
    bool stillShowing() =>
        mounted && asked == _context && identical(_config(printer), config);
    bool samePrinter() => mounted && _printerId == printer.id;
    bool sameUrl() =>
        samePrinter() && _url.text.trim() == (config.baseUrl ?? '');
    setState(() {
      _saving = true;
      _urlRefusal = null;
    });
    try {
      final saved = await ref
          .read(printersRepositoryProvider)
          .saveWledConfig(printer.id, config);
      if (!mounted) return;
      final current = stillShowing();
      setState(() {
        _saved[printer.id] = saved.wledConfig;
        // An edit made while the save was out stays a draft.
        if (identical(_drafts[printer.id], config)) _drafts.remove(printer.id);
      });
      if (!current) return;
      messenger.snack(l10n.wledSaved);
      // As on the web, whose saved printer row re-runs its preset load.
      final url = saved.wledConfig?.baseUrl;
      if (saved.wledConfig?.enabled == true && url != null) {
        _loadPresets(printer, url);
      }
    } on ApiException catch (e) {
      final refusal = e.statusCode == 422 && e.detail != null
          ? l10n.wledRefused(e.detail!)
          : null;
      if (refusal != null && sameUrl()) setState(() => _urlRefusal = refusal);
      showApiFailure(
        samePrinter() ? messenger : null,
        e,
        l10n,
        action: 'wled.save',
        message: refusal,
      );
    } on AppApiException catch (e) {
      showApiFailure(
        samePrinter() ? messenger : null,
        e,
        l10n,
        action: 'wled.save',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: dashAppBar(context, title: l10n.wledTitle),
        body: dashAsync(
          context,
          ref.watch(_wledPrintersProvider),
          onRetry: () => ref.invalidate(_wledPrintersProvider),
          data: (printers) {
            final printer = printers.firstWhereOrNull(
              (p) => p.id == _printerId,
            );
            if (printer == null) {
              return EmptyStateView(
                message: l10n.wledNoPrinters,
                icon: Icons.lightbulb_outline,
              );
            }
            return _form(context, l10n, printers, printer);
          },
        ),
      ),
    );
  }

  Widget _form(
    BuildContext context,
    AppLocalizations l10n,
    List<Printer> printers,
    Printer printer,
  ) {
    final t = DashTokens.of(context);
    final config = _config(printer);
    final on = config.enabled;
    final url = _url.text.trim();
    final timeout = parseFinishedTimeout(_timeout.text);
    final canSave = !_saving && timeout != null && (!on || url.isNotEmpty);
    final presets = _presets ?? const <WledPreset>[];

    return ListView(
      padding: screenListPadding(context),
      children: [
        InlineNote(
          l10n.wledDescription,
          icon: Icons.lightbulb_outline,
          padding: const EdgeInsets.symmetric(horizontal: DashSpace.xs),
        ),
        const SizedBox(height: DashSpace.md),
        dashCombo<int>(
          context,
          id: 'wled.printer',
          label: Text(l10n.wledPrinter),
          initialSelection: printer.id,
          entries: [
            for (final p in printers)
              DropdownMenuEntry(
                value: p.id,
                label: p.name,
                labelWidget: logTag('wled.printer.option', Text(p.name)),
              ),
          ],
          onSelected: (id) {
            final next = printers.firstWhereOrNull((p) => p.id == id);
            if (next != null && next.id != _printerId) _select(next);
          },
        ),
        const SizedBox(height: DashSpace.md),
        SettingsCard(
          rows: [
            SettingsSwitchRow(
              tag: 'wled.enabled',
              title: l10n.wledEnabled,
              subtitle: l10n.wledEnabledDesc,
              value: on,
              onChanged: (v) => _edit(printer, config.copyWith(enabled: v)),
            ),
          ],
        ),
        const SizedBox(height: DashSpace.md),
        TextField(
          controller: _url,
          enabled: on,
          autocorrect: false,
          keyboardType: TextInputType.url,
          onChanged: (text) => _urlChanged(printer, text),
          decoration: dashDecoration(
            t,
            labelText: l10n.wledUrl,
            hintText: 'http://wled.local',
            errorText: _urlRefusal,
            helperText: on && url.isEmpty ? l10n.wledUrlRequired : null,
          ),
        ).tagged('wled.url'),
        const SizedBox(height: DashSpace.sm),
        ButtonPair(
          primaryLabel: l10n.wledLoadPresets,
          secondaryLabel: l10n.wledTestConnection,
          primary: FilledButton.icon(
            onPressed: on && url.isNotEmpty && !_loadingPresets
                ? () => _loadPresets(printer, url)
                : null,
            icon: const Icon(Icons.refresh),
            label: Text(l10n.wledLoadPresets),
          ).tagged('wled.load_presets'),
          secondary: OutlinedButton.icon(
            onPressed: on && url.isNotEmpty && !_testingConnection
                ? () => _testConnection(printer, url)
                : null,
            icon: const Icon(Icons.wifi_tethering),
            label: Text(l10n.wledTestConnection),
          ).tagged('wled.test_connection'),
        ),
        ..._reachLines(l10n, t),
        const SizedBox(height: DashSpace.xl),
        SettingsSectionHeader(l10n.wledMappingHeader),
        InlineNote(
          l10n.wledSegmentHint,
          padding: const EdgeInsets.symmetric(horizontal: DashSpace.xs),
        ),
        const SizedBox(height: DashSpace.md),
        for (final state in WledState.values) ...[
          _stateRow(context, l10n, printer, config, state, presets, url),
          const SizedBox(height: DashSpace.sm),
        ],
        const SizedBox(height: DashSpace.sm),
        TextField(
          controller: _timeout,
          enabled: on,
          keyboardType: TextInputType.number,
          onChanged: (text) {
            final seconds = parseFinishedTimeout(text);
            if (seconds == null) return setState(() {});
            _edit(
              printer,
              config.copyWith(finishedTimeoutSeconds: () => seconds),
            );
          },
          decoration: dashDecoration(
            t,
            labelText: l10n.wledFinishedTimeout,
            helperText: l10n.wledFinishedTimeoutHint,
            errorText: timeout == null ? l10n.wledFinishedTimeoutInvalid : null,
          ),
        ).tagged('wled.finished_timeout'),
        const SizedBox(height: DashSpace.lg),
        FilledButton(
          onPressed: canSave ? () => _save(printer, config) : null,
          child: Text(l10n.wledSave),
        ).tagged('wled.save'),
      ],
    );
  }

  List<Widget> _reachLines(AppLocalizations l10n, DashTokens t) {
    final info = _info;
    final name = info?.name ?? 'WLED';
    final version = info?.version;
    final lines = [
      if (_connection == _Reach.online)
        (
          version == null
              ? l10n.wledConnected(name)
              : l10n.wledConnectedVersion(name, version),
          true,
        ),
      if (_connection == _Reach.offline) (l10n.wledUnreachable, false),
      if (_presetsReach == _Reach.online)
        (l10n.wledPresetsLoaded(_presets?.length ?? 0), true),
      if (_presetsReach == _Reach.offline) (l10n.wledPresetsOffline, false),
    ];
    return [
      for (final (text, ok) in lines)
        Padding(
          padding: const EdgeInsets.only(top: DashSpace.sm),
          child: InlineNote(
            text,
            icon: ok ? Icons.check_circle_outline : Icons.error_outline,
            padding: const EdgeInsets.symmetric(horizontal: DashSpace.xs),
            announce: true,
          ),
        ),
    ];
  }

  Widget _stateRow(
    BuildContext context,
    AppLocalizations l10n,
    Printer printer,
    WledConfig config,
    WledState state,
    List<WledPreset> presets,
    String url,
  ) {
    final selected = config.presets[state];
    final stateName = wledStateName(l10n, state);
    final missing = selected != null && presets.none((p) => p.id == selected);
    return Row(
      children: [
        Expanded(
          // Keyed so a printer switch or freshly loaded names redraw the text.
          child: KeyedSubtree(
            key: ValueKey((printer.id, state, selected, presets.length)),
            child: dashAnyOrOne<int>(
              context,
              id: 'wled.preset',
              label: Text(stateName),
              anyLabel: l10n.wledNoPreset,
              selected: selected,
              enabled: config.enabled,
              options: [
                if (missing) (selected, l10n.wledPresetSaved(selected)),
                for (final p in presets)
                  (p.id, l10n.wledPresetOption(p.name, p.id)),
              ],
              onPick: (id) {
                final next = {...config.presets}..remove(state);
                if (id != null) next[state] = id;
                _edit(printer, config.copyWith(presets: next));
              },
            ),
          ),
        ),
        IconButton(
          tooltip: l10n.wledTestPreset(stateName),
          onPressed:
              config.enabled &&
                  selected != null &&
                  url.isNotEmpty &&
                  !_testingPreset
              ? () => _testPreset(printer, url, selected)
              : null,
          icon: const Icon(Icons.play_arrow),
        ).tagged('wled.test_preset'),
      ],
    );
  }
}

String wledStateName(AppLocalizations l10n, WledState state) => switch (state) {
  WledState.idle => l10n.wledStateIdle,
  WledState.prepare => l10n.wledStatePrepare,
  WledState.printing => l10n.wledStatePrinting,
  WledState.paused => l10n.wledStatePaused,
  WledState.finished => l10n.wledStateFinished,
  WledState.error => l10n.wledStateError,
  WledState.queueWaiting => l10n.wledStateQueueWaiting,
  WledState.filamentProblem => l10n.wledStateFilamentProblem,
  WledState.hmsError => l10n.wledStateHmsError,
  WledState.offline => l10n.wledStateOffline,
};
