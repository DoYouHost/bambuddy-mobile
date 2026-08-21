import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/dash_text.dart';
import '../common/dash_progress.dart';
import '../common/dash_snack.dart';
import '../common/api_failure_snack.dart';
import '../../core/diagnostics/log_tag.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/models/makerworld.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import '../../providers.dart';
import '../files/library_thumbnail.dart';
import 'makerworld_providers.dart';
import 'makerworld_thumbnail.dart';

/// MakerWorld screen: paste model URL → resolve → pick plate → import (download) to library.
/// Download requires Bambu Cloud login; if missing, import action goes to settings login screen
/// (`/settings/cloud`) — login NOT built into this screen.
class MakerWorldScreen extends ConsumerStatefulWidget {
  const MakerWorldScreen({super.key});

  @override
  ConsumerState<MakerWorldScreen> createState() => _MakerWorldScreenState();
}

class _MakerWorldScreenState extends ConsumerState<MakerWorldScreen> {
  final _urlController = TextEditingController();

  /// `profileId` (or -1 for none) of plates currently importing.
  final _importing = <int>{};

  /// Plates imported in this session (for marking "in library").
  final _imported = <int>{};

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  AppLocalizations get _l10n => AppLocalizations.of(context);

  /// A download offer needs longer than the usual four seconds to be read, and
  /// must fade anyway — hence the explicit duration and `persist: false`.
  void _snack(String msg, {SnackBarAction? action}) =>
      ScaffoldMessenger.of(context).snack(
        msg,
        action: action,
        persist: false,
        duration: const Duration(seconds: 5),
      );

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
    // Login gate: without valid cloud token — go to login screen.
    final status = ref.read(makerworldStatusProvider).valueOrNull;
    if (status == null || !status.canDownload) {
      _snack(_l10n.mwLoginRequired);
      await context.push('/settings/cloud');
      if (!mounted) return;
      // Refresh login/integration status after return.
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
      showApiFailure(mounted ? ScaffoldMessenger.of(context) : null, e, _l10n,
          action: 'makerworld.import_plate');
    } finally {
      if (mounted) setState(() => _importing.remove(key));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n;
    final t = DashTokens.of(context);
    final resolveAsync = ref.watch(makerworldResolveProvider);
    final status = ref.watch(makerworldStatusProvider).valueOrNull;
    final canDownload = status?.canDownload ?? false;

    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: dashAppBar(context, title: l10n.makerworldTitle),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Text(
              l10n.mwIntro,
              style: t.bodySoft,
            ),
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
                if (!mounted) return;
                ref.invalidate(cloudAuthStatusProvider);
                ref.invalidate(makerworldStatusProvider);
              }),
            ],
            const SizedBox(height: 8),
            resolveAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: DashLoading(),
              ),
              error: (e, _) => _InlineError(
                message:
                    e is AppApiException ? e.localized(l10n) : l10n.ctrlFailed,
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
      ),
    );
  }
}

/// URL input bar + "Resolve" button.
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
    final t = DashTokens.of(context);
    // The button takes its height from the field instead of a constant. The
    // field is as tall as its prefix icon plus padding — and grows with the
    // system font size — so any number written here is wrong sooner or later;
    // 56 was already eight pixels too tall.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => onResolve(),
              style: t.bodyStrong,
              decoration: dashFieldDecoration(t, hintText: l10n.mwUrlHint)
                  .copyWith(
                prefixIcon: Icon(Icons.link, color: t.textTertiary),
              ),
            ).tagged('makerworld.url'),
          ),
          const SizedBox(width: 12),
          logTag(
            'makerworld.resolve',
            FilledButton.icon(
              style: dashPrimaryButtonStyle(t),
              onPressed: loading ? null : onResolve,
              icon: loading
                  ? DashSpinner(color: Color(0xFF0A0C08),
                    )
                  : const Icon(Icons.arrow_forward),
              label: Text(l10n.mwResolve),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Sign in to download" banner — when no valid cloud token.
class _LoginBanner extends StatelessWidget {
  const _LoginBanner({required this.onSignIn});

  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.accentOrange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.accentOrange.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off, color: t.accentOrange),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l10n.mwLoginRequired,
              style: t.body,
            ),
          ),
          const SizedBox(width: 8),
          logTag(
            'makerworld.sign_in',
            FilledButton(
              style: dashPrimaryButtonStyle(t),
              onPressed: onSignIn,
              child: Text(l10n.cloudSignIn),
            ),
          ),
        ],
      ),
    );
  }
}

/// Resolved model section: header + plate list.
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
  /// How many plates to show before collapse — some models have dozens.
  static const _collapsedCount = 5;

  bool _expanded = false;

  @override
  void didUpdateWidget(_ResolvedModel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // New model (different URL/id) — collapse again.
    if (oldWidget.model.modelId != widget.model.modelId) _expanded = false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final model = widget.model;
    final total = model.instances.length;
    final overflowing = total > _collapsedCount;
    final visible = (_expanded || !overflowing)
        ? model.instances
        : model.instances.take(_collapsedCount).toList();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: t.cardGradient,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: t.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: MakerWorldThumbnail(
                    coverUrl: model.design.coverUrl, size: 72),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      model.design.title ?? l10n.mwUntitledModel,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.titleMd,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.mwPlatesCount(model.instances.length),
                      style: t.monoLabel,
                    ),
                  ],
                ),
              ),
            ],
          ),
          Divider(height: 24, color: t.hairline),
          if (model.instances.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                l10n.mwNoPlates,
                style: t.bodyPlain,
              ),
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
                child: logTag(
                  'makerworld.toggle_plates',
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: t.accentGreenInk),
                    onPressed: () => setState(() => _expanded = !_expanded),
                    icon: Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more),
                    label: Text(_expanded
                        ? l10n.mwShowLess
                        : l10n.mwShowAllPlates(total)),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Single plate (instance) row with import button.
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
    final t = DashTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: MakerWorldThumbnail(coverUrl: plate.coverUrl, size: 48),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              plate.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: t.body,
            ),
          ),
          const SizedBox(width: 8),
          if (imported)
            TextButton.icon(
              onPressed: null,
              style: TextButton.styleFrom(
                  foregroundColor: t.accentGreenInk.withValues(alpha: 0.6)),
              icon: const Icon(Icons.check_circle, size: 18),
              label: Text(l10n.mwInLibrary),
            ).tagged('makerworld.plate')
          else
            logTag(
              'makerworld.import_plate',
              FilledButton.icon(
                style: dashPrimaryButtonStyle(t).copyWith(
                  padding: const WidgetStatePropertyAll(
                      EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
                ),
                onPressed: importing ? null : onImport,
                icon: importing
                    ? DashSpinner(size: 16, color: Color(0xFF0A0C08),
                      )
                    : const Icon(Icons.download, size: 18),
                label: Text(l10n.mwImport),
              ),
            ),
        ],
      ),
    );
  }
}

/// "Recent imports" section.
class _RecentImports extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final async = ref.watch(makerworldRecentImportsProvider);
    final emptyStyle = t.bodySoft.copyWith(color: t.textTertiary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.mwRecentImports,
          style: t.titleSm,
        ),
        const SizedBox(height: 8),
        async.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: DashLoading(),
          ),
          error: (_, _) => Text(l10n.mwNoRecent, style: emptyStyle),
          data: (items) => items.isEmpty
              ? Text(l10n.mwNoRecent, style: emptyStyle)
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
    final t = DashTokens.of(context);
    final source = item.sourceUrl;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: logTag(
          'makerworld.recent_import',
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => context.push('/files'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: t.subCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: t.subCardBorder),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: LibraryThumbnail(
                      fileId: item.libraryFileId,
                      hasThumbnail: item.hasThumbnail,
                      size: 48,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item.filename,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.body,
                    ),
                  ),
                  if (source != null)
                    logTag(
                      'makerworld.open_source',
                      IconButton(
                        tooltip: l10n.mwOpenOnMakerworld,
                        icon: Icon(Icons.open_in_new,
                            size: 18, color: t.textSecondary),
                        onPressed: () => launchUrl(
                          Uri.parse(source),
                          mode: LaunchMode.externalApplication,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Inline error with retry button.
class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(Icons.error_outline, size: 40, color: t.danger),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: t.bodyPlain,
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: t.textPrimary,
              side: BorderSide(color: t.cardBorder),
            ),
            onPressed: onRetry,
            child: Text(l10n.retry),
          ).tagged('makerworld.error_action'),
        ],
      ),
    );
  }
}
