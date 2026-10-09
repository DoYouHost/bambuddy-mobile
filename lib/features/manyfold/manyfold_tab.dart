import 'dart:async';

import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/models/current_user.dart';
import '../../core/models/manyfold.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common/dash_async.dart';
import '../common/dash_search_field.dart';
import 'manyfold_model_screen.dart';
import 'manyfold_providers.dart';
import 'manyfold_widgets.dart';

/// The Manyfold tab of Model Sources (#1471, the web's `ManyfoldTab`): search
/// and page through the connected library, open a model, or tick models and
/// import all their printable files at once.
class ManyfoldTab extends ConsumerStatefulWidget {
  const ManyfoldTab({super.key, required this.status});

  final ManyfoldStatus status;

  @override
  ConsumerState<ManyfoldTab> createState() => _ManyfoldTabState();
}

class _ManyfoldTabState extends ConsumerState<ManyfoldTab> {
  Timer? _debounce;
  String _query = '';
  int _page = 1;

  /// Models ticked in the grid, kept across pages and searches (id → name).
  final _picked = <String, String>{};
  int? _folderId;

  /// "Reading models 2/5" or "Importing 3/9" while the ticked models import.
  String? _progress;

  /// The page shown while the next one loads, as the web's
  /// `placeholderData`, so paging does not blank the grid.
  ManyfoldModelPage? _shown;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// Every query is a round trip to the user's Manyfold, so typing waits for a
  /// pause instead of asking per keystroke (the web asks on submit).
  void _onSearchChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted || text.trim() == _query) return;
      setState(() {
        _query = text.trim();
        _page = 1;
      });
    });
  }

  void _togglePicked(ManyfoldModelSummary model) => setState(() {
    if (_picked.remove(model.id) == null) _picked[model.id] = model.name;
  });

  Future<void> _openModel(ManyfoldModelSummary model) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              ManyfoldModelScreen(modelId: model.id, title: model.name),
        ),
      );

  /// Every printable file of the ticked models that is not in the library
  /// yet. The models are read one after another first, then their files
  /// imported.
  Future<void> _importPicked() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(manyfoldRepositoryProvider);
    final picked = Map.of(_picked);
    final items = <ManyfoldImportItem>[];
    final unreadable = <String>[];
    var i = 0;
    for (final MapEntry(key: id, value: name) in picked.entries) {
      setState(() => _progress = l10n.mfCollectProgress(++i, picked.length));
      try {
        final model = await repo.model(id);
        for (final f in model.importCandidates) {
          items.add((
            modelId: model.id,
            fileId: f.id,
            name: '${model.name}: ${f.name}',
          ));
        }
      } on Object catch (e) {
        if (e is! ManyfoldFailure && e is! AppApiException) rethrow;
        unreadable.add(name);
      }
      if (!mounted) return;
    }
    if (unreadable.isNotEmpty) {
      messenger.snack(l10n.mfModelsUnreadable(manyfoldListNames(unreadable)));
    }
    await importManyfoldFiles(
      repo,
      items,
      folderId: _folderId,
      messenger: messenger,
      l10n: l10n,
      mounted: () => mounted,
      action: 'manyfold.import_models',
      onProgress: (current, total) {
        if (mounted) {
          setState(() => _progress = l10n.mfImportProgress(current, total));
        }
      },
    );
    if (mounted) {
      setState(() {
        _progress = null;
        _picked.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    if (!widget.status.configured) {
      return _NotConnected(l10n: l10n);
    }
    final canImport = ref.watch(permissionProvider(Permissions.manyfoldImport));
    final key = (_query, _page);
    final listing = ref.watch(manyfoldModelsProvider(key));
    if (listing.valueOrNull case final page?) _shown = page;
    final busy = _progress != null;

    return ListView(
      padding: withSystemNavInset(
        context,
        const EdgeInsets.fromLTRB(
          DashSpace.gutter,
          DashSpace.lg,
          DashSpace.gutter,
          DashSpace.xxl,
        ),
      ),
      children: [
        Text(l10n.mfDescription, style: t.bodySoft),
        const SizedBox(height: DashSpace.lg),
        DashSearchField(
          id: 'manyfold.search',
          hintText: l10n.mfSearchPlaceholder,
          onChanged: _onSearchChanged,
        ),
        const SizedBox(height: DashSpace.lg),
        if (listing.hasError && !listing.isLoading)
          dashAsync(
            context,
            listing,
            onRetry: () => ref.invalidate(manyfoldModelsProvider(key)),
            fallbackMessage: manyfoldErrorText(listing.error!, l10n),
            data: (_) => const SizedBox.shrink(),
          )
        else if (_shown == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: DashSpace.xxl),
            child: DashLoading(),
          )
        else if (_shown!.models.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: DashSpace.xl),
            child: Text(
              l10n.mfNoModels,
              textAlign: TextAlign.center,
              style: t.bodySoft,
            ),
          )
        else
          ..._listing(context, _shown!, canImport: canImport, busy: busy),
      ],
    );
  }

  List<Widget> _listing(
    BuildContext context,
    ManyfoldModelPage page, {
    required bool canImport,
    required bool busy,
  }) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final loading = ref
        .watch(manyfoldModelsProvider((_query, _page)))
        .isLoading;
    return [
      Row(
        children: [
          Expanded(
            child: Text(l10n.mfModelCount(page.total), style: t.monoLabel),
          ),
          if (canImport)
            TextButton(
              onPressed: busy
                  ? null
                  : () => setState(() {
                      for (final m in page.models) {
                        _picked[m.id] = m.name;
                      }
                    }),
              child: Text(l10n.mfSelectPage),
            ).tagged('manyfold.select_page'),
        ],
      ),
      if (canImport && _picked.isNotEmpty) ...[
        const SizedBox(height: DashSpace.sm),
        _SelectionBar(
          count: _picked.length,
          folderId: _folderId,
          progress: _progress,
          onFolder: (id) => setState(() => _folderId = id),
          onImport: _importPicked,
          onClear: () => setState(_picked.clear),
        ),
      ],
      const SizedBox(height: DashSpace.md),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: DashSpace.md,
        crossAxisSpacing: DashSpace.md,
        childAspectRatio: _tileAspect,
        children: [
          for (final model in page.models)
            _ModelTile(
              model: model,
              picked: _picked.containsKey(model.id),
              canPick: canImport,
              // Locked while the ticked models import, so a file cannot be
              // imported twice at once from the model view.
              enabled: !busy,
              onOpen: () => _openModel(model),
              onPick: () => _togglePicked(model),
            ),
        ],
      ),
      if (page.hasPrevious || page.hasNext) ...[
        const SizedBox(height: DashSpace.lg),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: !page.hasPrevious || loading
                  ? null
                  : () => setState(() => _page = page.page - 1),
              icon: const Icon(Icons.chevron_left),
              label: Text(l10n.mfPrevious),
            ).tagged('manyfold.prev_page'),
            Expanded(
              child: Text(
                l10n.mfPage(page.page),
                textAlign: TextAlign.center,
                style: t.monoLabel,
              ),
            ),
            OutlinedButton.icon(
              onPressed: !page.hasNext || loading
                  ? null
                  : () => setState(() => _page = page.page + 1),
              icon: const Icon(Icons.chevron_right),
              label: Text(l10n.mfNext),
            ).tagged('manyfold.next_page'),
          ],
        ),
      ],
    ];
  }

  /// Square preview plus two lines of name.
  static const _tileAspect = 0.78;
}

class _ModelTile extends StatelessWidget {
  const _ModelTile({
    required this.model,
    required this.picked,
    required this.canPick,
    required this.enabled,
    required this.onOpen,
    required this.onPick,
  });

  final ManyfoldModelSummary model;
  final bool picked;
  final bool canPick;
  final bool enabled;
  final VoidCallback onOpen;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: enabled ? onOpen : null,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: t.subCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: picked ? t.accentGreen : t.subCardBorder,
              width: picked ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Stack(
                children: [
                  ManyfoldPreview(modelId: model.id),
                  if (canPick)
                    Positioned(
                      top: DashSpace.xs,
                      right: DashSpace.xs,
                      child: Checkbox(
                        value: picked,
                        semanticLabel: l10n.mfSelectModel(model.name),
                        onChanged: enabled ? (_) => onPick() : null,
                      ).tagged('manyfold.pick_model', selected: picked),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(DashSpace.sm),
                child: Text(
                  model.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.body,
                ),
              ),
            ],
          ),
        ),
      ),
    ).tagged('manyfold.model');
  }
}

/// What the ticked models import into, and the button that does it.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.folderId,
    required this.progress,
    required this.onFolder,
    required this.onImport,
    required this.onClear,
  });

  final int count;
  final int? folderId;
  final String? progress;
  final ValueChanged<int?> onFolder;
  final VoidCallback onImport;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final progress = this.progress;
    return Container(
      padding: const EdgeInsets.all(DashSpace.md),
      decoration: t.cardBox,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.mfModelsSelected(count), style: t.bodyStrong),
          const SizedBox(height: DashSpace.md),
          ManyfoldFolderCombo(
            value: folderId,
            onChanged: onFolder,
            enabled: progress == null,
          ),
          const SizedBox(height: DashSpace.md),
          if (progress != null)
            Row(
              children: [
                const DashSpinner(size: 16),
                const SizedBox(width: DashSpace.sm),
                Expanded(child: Text(progress, style: t.bodySoft)),
              ],
            )
          else
            ButtonPair(
              primaryLabel: l10n.mfImportModels,
              secondaryLabel: l10n.mfClearSelection,
              primary: FilledButton.icon(
                onPressed: onImport,
                icon: const Icon(Icons.download),
                label: Text(l10n.mfImportModels),
              ).tagged('manyfold.import_models'),
              secondary: OutlinedButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.clear),
                label: Text(l10n.mfClearSelection),
              ).tagged('manyfold.clear_selection'),
            ),
        ],
      ),
    );
  }
}

/// A browsing user before Manyfold is connected. Who may connect it gets the
/// connection form instead.
class _NotConnected extends StatelessWidget {
  const _NotConnected({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return ListView(
      padding: const EdgeInsets.all(DashSpace.gutter),
      children: [
        Container(
          padding: const EdgeInsets.all(DashSpace.xl),
          decoration: t.cardBox,
          child: Column(
            children: [
              Icon(Icons.link_off, size: 40, color: t.textTertiary),
              const SizedBox(height: DashSpace.md),
              Text(
                l10n.mfNotConnectedTitle,
                textAlign: TextAlign.center,
                style: t.titleSm,
              ),
              const SizedBox(height: DashSpace.sm),
              Text(
                l10n.mfNotConnectedBody,
                textAlign: TextAlign.center,
                style: t.bodySoft,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
