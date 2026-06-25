import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/models/makerworld.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import '../../providers.dart';
import '../files/library_thumbnail.dart';
import 'makerworld_providers.dart';
import 'makerworld_thumbnail.dart';

/// Ekran MakerWorld: wklej URL modelu → rozwiąż → wybierz płytę → importuj
/// (pobierz) do biblioteki. Pobieranie wymaga zalogowania do chmury Bambu;
/// gdy go brak, akcja importu przenosi na ekran logowania w ustawieniach
/// (`/settings/cloud`) — logowanie NIE jest wbudowane w ten ekran.
class MakerWorldScreen extends ConsumerStatefulWidget {
  const MakerWorldScreen({super.key});

  @override
  ConsumerState<MakerWorldScreen> createState() => _MakerWorldScreenState();
}

class _MakerWorldScreenState extends ConsumerState<MakerWorldScreen> {
  final _urlController = TextEditingController();

  /// `profileId` (lub -1 dla braku) płyt aktualnie importowanych.
  final _importing = <int>{};

  /// Płyty zaimportowane w tej sesji (do oznaczenia „w bibliotece").
  final _imported = <int>{};

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  AppLocalizations get _l10n => AppLocalizations.of(context);

  void _snack(String msg, {SnackBarAction? action}) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        action: action,
        // SnackBar.persist domyślnie = (action != null), więc z akcją NIE
        // znika sam. Wymuszamy auto-zamknięcie po czasie — akcja zostaje
        // klikalna, ale pasek nie wisi w nieskończoność.
        persist: false,
        duration: const Duration(seconds: 5),
      ));

  int _key(int? profileId) => profileId ?? -1;

  Future<void> _resolve() async {
    FocusScope.of(context).unfocus();
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      _snack(_l10n.mwEnterUrl);
      return;
    }
    _imported.clear();
    await ref.read(makerworldResolveProvider.notifier).resolve(url);
  }

  Future<void> _import(MakerWorldResolvedModel model, MakerWorldInstance plate) async {
    // Bramka logowania: bez ważnego tokenu chmury — na ekran logowania.
    final status = ref.read(makerworldStatusProvider).valueOrNull;
    if (status == null || !status.canDownload) {
      _snack(_l10n.mwLoginRequired);
      await context.push('/settings/cloud');
      // Po powrocie odśwież stan logowania/integracji.
      ref.invalidate(cloudAuthStatusProvider);
      ref.invalidate(makerworldStatusProvider);
      return;
    }

    final key = _key(plate.profileId);
    setState(() => _importing.add(key));
    try {
      final res = await ref.read(makerworldRepositoryProvider).import(
            modelId: model.modelId,
            profileId: plate.profileId,
          );
      if (!mounted) return;
      setState(() => _imported.add(key));
      ref.invalidate(makerworldRecentImportsProvider);
      _snack(
        res.wasExisting ? _l10n.mwAlreadyInLibrary : _l10n.mwImported,
        action: SnackBarAction(
          label: _l10n.mwViewInFiles,
          onPressed: () => context.push('/files'),
        ),
      );
    } on AppApiException catch (e) {
      if (mounted) _snack(e.localized(_l10n));
    } finally {
      if (mounted) setState(() => _importing.remove(key));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n;
    final resolveAsync = ref.watch(makerworldResolveProvider);
    final status = ref.watch(makerworldStatusProvider).valueOrNull;
    final canDownload = status?.canDownload ?? false;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.makerworldTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text(l10n.mwIntro, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
          _UrlBar(
            controller: _urlController,
            loading: resolveAsync.isLoading,
            onResolve: _resolve,
          ),
          if (!canDownload) ...[
            const SizedBox(height: 16),
            _LoginBanner(onSignIn: () async {
              await context.push('/settings/cloud');
              ref.invalidate(cloudAuthStatusProvider);
              ref.invalidate(makerworldStatusProvider);
            }),
          ],
          const SizedBox(height: 8),
          resolveAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => _InlineError(
              message: e is AppApiException ? e.localized(l10n) : l10n.ctrlFailed,
              onRetry: _resolve,
            ),
            data: (model) => model == null
                ? const SizedBox.shrink()
                : _ResolvedModel(
                    model: model,
                    importing: _importing,
                    imported: _imported,
                    onImport: (plate) => _import(model, plate),
                    keyOf: _key,
                  ),
          ),
          const SizedBox(height: 24),
          _RecentImports(),
        ],
      ),
    );
  }
}

/// Pasek wejścia URL-a + przycisk „Rozwiąż".
class _UrlBar extends StatelessWidget {
  const _UrlBar({
    required this.controller,
    required this.loading,
    required this.onResolve,
  });

  final TextEditingController controller;
  final bool loading;
  final VoidCallback onResolve;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => onResolve(),
            decoration: InputDecoration(
              hintText: l10n.mwUrlHint,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.link),
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          height: 56,
          child: FilledButton.icon(
            onPressed: loading ? null : onResolve,
            icon: loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.arrow_forward),
            label: Text(l10n.mwResolve),
          ),
        ),
      ],
    );
  }
}

/// Baner „zaloguj się, żeby pobierać" — gdy brak ważnego tokenu chmury.
class _LoginBanner extends StatelessWidget {
  const _LoginBanner({required this.onSignIn});

  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off, color: scheme.onSecondaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l10n.mwLoginRequired,
              style: TextStyle(color: scheme.onSecondaryContainer),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(onPressed: onSignIn, child: Text(l10n.cloudSignIn)),
        ],
      ),
    );
  }
}

/// Sekcja rozwiązanego modelu: nagłówek + lista płyt.
class _ResolvedModel extends StatefulWidget {
  const _ResolvedModel({
    required this.model,
    required this.importing,
    required this.imported,
    required this.onImport,
    required this.keyOf,
  });

  final MakerWorldResolvedModel model;
  final Set<int> importing;
  final Set<int> imported;
  final void Function(MakerWorldInstance plate) onImport;
  final int Function(int? profileId) keyOf;

  @override
  State<_ResolvedModel> createState() => _ResolvedModelState();
}

class _ResolvedModelState extends State<_ResolvedModel> {
  /// Ile płyt pokazujemy przed zwinięciem — niektóre modele mają ich dziesiątki.
  static const _collapsedCount = 5;

  bool _expanded = false;

  @override
  void didUpdateWidget(_ResolvedModel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Nowy model (inny URL/identyfikator) — zwiń z powrotem.
    if (oldWidget.model.modelId != widget.model.modelId) _expanded = false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final model = widget.model;
    final total = model.instances.length;
    final overflowing = total > _collapsedCount;
    final visible = (_expanded || !overflowing)
        ? model.instances
        : model.instances.take(_collapsedCount).toList();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MakerWorldThumbnail(coverUrl: model.design.coverUrl, size: 72),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        model.design.title ?? l10n.mwUntitledModel,
                        style: theme.textTheme.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.mwPlatesCount(model.instances.length),
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            if (model.instances.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(l10n.mwNoPlates,
                    style: theme.textTheme.bodyMedium),
              )
            else ...[
              ...visible.map((plate) {
                final key = widget.keyOf(plate.profileId);
                return _PlateRow(
                  plate: plate,
                  importing: widget.importing.contains(key),
                  imported: widget.imported.contains(key),
                  onImport: () => widget.onImport(plate),
                );
              }),
              if (overflowing)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _expanded = !_expanded),
                    icon: Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more),
                    label: Text(_expanded
                        ? l10n.mwShowLess
                        : l10n.mwShowAllPlates(total)),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Wiersz pojedynczej płyty (instancji) z przyciskiem importu.
class _PlateRow extends StatelessWidget {
  const _PlateRow({
    required this.plate,
    required this.importing,
    required this.imported,
    required this.onImport,
  });

  final MakerWorldInstance plate;
  final bool importing;
  final bool imported;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          MakerWorldThumbnail(coverUrl: plate.coverUrl, size: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              plate.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(width: 8),
          if (imported)
            TextButton.icon(
              onPressed: null,
              icon: const Icon(Icons.check_circle, size: 18),
              label: Text(l10n.mwInLibrary),
            )
          else
            FilledButton.tonalIcon(
              onPressed: importing ? null : onImport,
              icon: importing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download, size: 18),
              label: Text(l10n.mwImport),
            ),
        ],
      ),
    );
  }
}

/// Sekcja „ostatnie importy".
class _RecentImports extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final async = ref.watch(makerworldRecentImportsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.mwRecentImports, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        async.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => Text(l10n.mwNoRecent,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          data: (items) => items.isEmpty
              ? Text(l10n.mwNoRecent,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant))
              : Column(
                  children: [
                    for (final item in items) _RecentRow(item: item),
                  ],
                ),
        ),
      ],
    );
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.item});

  final MakerWorldRecentImport item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final source = item.sourceUrl;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: LibraryThumbnail(
        fileId: item.libraryFileId,
        hasThumbnail: item.hasThumbnail,
        size: 48,
      ),
      title: Text(
        item.filename,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: source == null
          ? null
          : IconButton(
              tooltip: l10n.mwOpenOnMakerworld,
              icon: const Icon(Icons.open_in_new, size: 18),
              onPressed: () => launchUrl(
                Uri.parse(source),
                mode: LaunchMode.externalApplication,
              ),
            ),
      onTap: () => context.push('/files'),
    );
  }
}

/// Inline-błąd z przyciskiem ponowienia.
class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(Icons.error_outline,
              size: 40, color: Theme.of(context).colorScheme.error),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: Text(l10n.retry)),
        ],
      ),
    );
  }
}
