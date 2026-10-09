import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/models/current_user.dart';
import '../../core/models/manyfold.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common/dash_async.dart';
import '../common/web_link.dart';
import '../slicer/slice_providers.dart';
import '../slicer/slice_screen.dart';
import 'manyfold_providers.dart';
import 'manyfold_widgets.dart';

/// One Manyfold model: its details and files, each importable into the
/// library — the web's `ManyfoldModelView`, as a screen of its own.
class ManyfoldModelScreen extends ConsumerStatefulWidget {
  const ManyfoldModelScreen({
    super.key,
    required this.modelId,
    required this.title,
  });

  final String modelId;
  final String title;

  @override
  ConsumerState<ManyfoldModelScreen> createState() =>
      _ManyfoldModelScreenState();
}

class _ManyfoldModelScreenState extends ConsumerState<ManyfoldModelScreen> {
  int? _folderId;

  /// The file whose own Import button is spinning.
  String? _importingFileId;
  final _checked = <String>{};

  /// "Importing 2/5" while a bulk import runs.
  String? _progress;

  bool get _busy => _progress != null || _importingFileId != null;

  void _reload() => ref.invalidate(manyfoldModelProvider(widget.modelId));

  Future<void> _importOne(ManyfoldFile file) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _importingFileId = file.id);
    try {
      final result = await ref
          .read(manyfoldRepositoryProvider)
          .import(
            modelId: widget.modelId,
            fileId: file.id,
            folderId: _folderId,
          );
      messenger.snack(
        result.wasExisting
            ? l10n.mfAlreadyInLibrary
            : l10n.mfImported(result.filename),
      );
      if (mounted) _reload();
    } on Object catch (e) {
      if (e is! ManyfoldFailure && e is! AppApiException) rethrow;
      showManyfoldFailure(
        mounted ? messenger : null,
        e,
        l10n,
        action: 'manyfold.import_file',
      );
    } finally {
      if (mounted) setState(() => _importingFileId = null);
    }
  }

  Future<void> _importMany(List<ManyfoldFile> files, String action) async {
    final l10n = AppLocalizations.of(context);
    await importManyfoldFiles(
      ref.read(manyfoldRepositoryProvider),
      [
        for (final f in files)
          (modelId: widget.modelId, fileId: f.id, name: f.name),
      ],
      folderId: _folderId,
      messenger: ScaffoldMessenger.of(context),
      l10n: l10n,
      mounted: () => mounted,
      action: action,
      onProgress: (current, total) {
        if (mounted) {
          setState(() => _progress = l10n.mfImportProgress(current, total));
        }
      },
    );
    if (!mounted) return;
    setState(() {
      _progress = null;
      _checked.clear();
    });
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final model = ref.watch(manyfoldModelProvider(widget.modelId));
    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: dashAppBar(context, title: widget.title),
        body: dashAsync(
          context,
          model,
          onRetry: _reload,
          fallbackMessage: model.hasError
              ? manyfoldErrorText(model.error!, l10n)
              : null,
          data: (model) => ListView(
            padding: withSystemNavInset(
              context,
              const EdgeInsets.fromLTRB(
                DashSpace.gutter,
                DashSpace.sm,
                DashSpace.gutter,
                DashSpace.xxl,
              ),
            ),
            children: [
              _Header(model: model),
              const SizedBox(height: DashSpace.lg),
              _files(context, model),
            ],
          ),
        ),
      ),
    );
  }

  Widget _files(BuildContext context, ManyfoldModel model) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final canImport = ref.watch(permissionProvider(Permissions.manyfoldImport));
    final canSlice = ref.watch(slicerEnabledProvider).orFalse;
    final candidates = model.importCandidates;
    final selected = [
      for (final f in candidates)
        if (_checked.contains(f.id)) f,
    ];
    final allSelected =
        candidates.isNotEmpty && selected.length == candidates.length;
    final picking = canImport && candidates.isNotEmpty;
    final progress = _progress;

    return Container(
      padding: const EdgeInsets.all(DashSpace.lg),
      decoration: t.cardBox,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.mfFiles, style: t.titleSm),
          if (canImport) ...[
            const SizedBox(height: DashSpace.md),
            ManyfoldFolderCombo(
              value: _folderId,
              onChanged: (id) => setState(() => _folderId = id),
              enabled: !_busy,
            ),
          ],
          if (picking) ...[
            const SizedBox(height: DashSpace.sm),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              tristate: true,
              value: allSelected ? true : (selected.isEmpty ? false : null),
              onChanged: _busy
                  ? null
                  : (_) => setState(() {
                      if (allSelected) {
                        _checked.clear();
                      } else {
                        _checked.addAll(candidates.map((f) => f.id));
                      }
                    }),
              title: Text(l10n.mfSelectAll, style: t.body),
            ).tagged('manyfold.select_all', selected: allSelected),
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
                primaryLabel: l10n.mfImportSelected(selected.length),
                secondaryLabel: l10n.mfImportAll,
                primary: FilledButton.icon(
                  onPressed: _busy || selected.isEmpty
                      ? null
                      : () => _importMany(selected, 'manyfold.import_selected'),
                  icon: const Icon(Icons.download),
                  label: Text(l10n.mfImportSelected(selected.length)),
                ).tagged('manyfold.import_selected'),
                secondary: OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _importMany(candidates, 'manyfold.import_all'),
                  icon: const Icon(Icons.download_for_offline_outlined),
                  label: Text(l10n.mfImportAll),
                ).tagged('manyfold.import_all'),
              ),
          ],
          const SizedBox(height: DashSpace.sm),
          if (model.files.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: DashSpace.sm),
              child: Text(l10n.mfNoFiles, style: t.bodySoft),
            )
          else
            for (final file in model.files)
              _FileRow(
                file: file,
                checkbox: picking,
                checked: _checked.contains(file.id),
                canImport: canImport,
                canSlice: canSlice,
                importing: _importingFileId == file.id,
                busy: _busy,
                onCheck: () => setState(() {
                  if (!_checked.remove(file.id)) _checked.add(file.id);
                }),
                onImport: () => _importOne(file),
              ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.model});

  final ManyfoldModel model;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final caption = model.caption;
    final description = model.description;
    final license = model.license;
    return Container(
      padding: const EdgeInsets.all(DashSpace.lg),
      decoration: t.cardBox,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: ManyfoldPreview(modelId: model.id, size: _previewSize),
              ),
              const SizedBox(width: DashSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(model.name, style: t.titleMd),
                    if (caption != null && caption.isNotEmpty) ...[
                      const SizedBox(height: DashSpace.xs),
                      Text(caption, style: t.bodySoft),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (description != null && description.isNotEmpty) ...[
            const SizedBox(height: DashSpace.md),
            Text(description, style: t.body),
          ],
          if (model.tags.isNotEmpty) ...[
            const SizedBox(height: DashSpace.md),
            Wrap(
              spacing: DashSpace.sm,
              runSpacing: DashSpace.sm,
              children: [
                for (final tag in model.tags)
                  DashPill(label: tag, accent: t.textTertiary, dense: true),
              ],
            ),
          ],
          const SizedBox(height: DashSpace.md),
          Row(
            children: [
              if (license != null && license.isNotEmpty)
                Expanded(
                  child: Text(
                    '${l10n.mfLicense}: $license',
                    style: t.monoLabel,
                  ),
                )
              else
                const Spacer(),
              if (model.url.isNotEmpty)
                TextButton.icon(
                  onPressed: () => openWebLink(context, model.url),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: Text(l10n.mfOpenInManyfold),
                ).tagged('manyfold.open_in_manyfold'),
            ],
          ),
        ],
      ),
    );
  }

  static const _previewSize = 96.0;
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.file,
    required this.checkbox,
    required this.checked,
    required this.canImport,
    required this.canSlice,
    required this.importing,
    required this.busy,
    required this.onCheck,
    required this.onImport,
  });

  final ManyfoldFile file;

  /// Whether the row keeps the checkbox column, even when this file has none.
  final bool checkbox;
  final bool checked;
  final bool canImport;
  final bool canSlice;
  final bool importing;
  final bool busy;
  final VoidCallback onCheck;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final imported = file.libraryFile;
    final pickable = file.importable && imported == null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DashSpace.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (checkbox)
            SizedBox.square(
              dimension: kMinInteractiveDimension,
              child: pickable
                  ? Checkbox(
                      value: checked,
                      semanticLabel: l10n.mfSelectFile(file.name),
                      onChanged: busy ? null : (_) => onCheck(),
                    ).tagged('manyfold.pick_file', selected: checked)
                  : null,
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    DashPill(
                      label: file.typeLabel,
                      accent: t.textTertiary,
                      dense: true,
                    ),
                    const SizedBox(width: DashSpace.sm),
                    Expanded(
                      child: Text(
                        file.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.body,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: DashSpace.xs),
                if (!file.importable)
                  Text(l10n.mfNotImportable, style: t.bodySoft)
                else if (imported != null)
                  Wrap(
                    spacing: DashSpace.sm,
                    runSpacing: DashSpace.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      DashPill(
                        label: l10n.mfInLibrary,
                        accent: t.accentGreen,
                        accentInk: t.accentGreenInk,
                        icon: Icons.check_circle,
                        dense: true,
                      ),
                      TextButton(
                        onPressed: () => context.push(
                          imported.folderId == null
                              ? '/files'
                              : '/files?folder=${imported.folderId}',
                        ),
                        child: Text(l10n.mfShowInLibrary),
                      ).tagged('manyfold.show_in_library'),
                      if (canSlice && !_sliced(imported.filename))
                        TextButton(
                          onPressed: () => showSliceScreen(
                            context,
                            SliceTarget.libraryFile(
                              imported.id,
                              imported.filename,
                            ),
                          ),
                          child: Text(l10n.sliceAction),
                        ).tagged('manyfold.slice'),
                    ],
                  )
                else if (canImport)
                  FilledButton.tonalIcon(
                    onPressed: busy ? null : onImport,
                    icon: importing
                        ? const DashSpinner(size: 16)
                        : const Icon(Icons.download, size: 18),
                    label: Text(importing ? l10n.mfImporting : l10n.mfImport),
                  ).tagged('manyfold.import_file'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Already sliced output — `LibraryFile.isPrintable`'s name rule, the one the
  /// file manager offers Slice by.
  static bool _sliced(String filename) {
    final name = filename.toLowerCase();
    return name.endsWith('.gcode') || name.endsWith('.gcode.3mf');
  }
}
