import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/diagnostics/log_tag.dart';
import '../../core/models/library_file.dart';
import '../../core/models/library_tag.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import '../../providers.dart';
import '../common/confirm_dialog.dart';
import '../common/prompt_name_dialog.dart';
import 'file_manager_providers.dart';

/// Bottom sheets for library tags: the filter, per-file assignment, bulk
/// assignment, and catalog upkeep.
///
/// All four read the catalog from [libraryTagsProvider], so a tag created or
/// renamed in one of them shows up in the others without any plumbing — and a
/// server with no tag routes never gets here, because the caller hides the
/// entry points (see [libraryTagsSupported]).

/// A tag as it appears on a file tile: label only, no colour and no icon —
/// upstream deliberately kept tags plain so a file can carry several without
/// the row turning into a paint chart.
class TagChip extends StatelessWidget {
  const TagChip(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: t.accentGreen.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: t.accentGreen.withValues(alpha: 0.30)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: DashTokens.fontUi,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: t.accentGreenInk,
        ),
      ),
    );
  }
}

/// Tag filter — multi-select with AND semantics, applied library-wide.
Future<void> showTagFilterSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _TagFilterSheet(),
    );

/// Tags of a single file. Returns `true` when the assignment changed, so the
/// caller knows whether to refresh the listing.
Future<bool> showFileTagsSheet(BuildContext context, LibraryFile file) async =>
    await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _FileTagsSheet(file: file),
    ) ??
    false;

/// Tags across the selected files (add / remove / replace).
/// Returns `true` when something was applied.
Future<bool> showBulkTagsSheet(
  BuildContext context,
  List<int> fileIds,
) async =>
    await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _BulkTagsSheet(fileIds: fileIds),
    ) ??
    false;

/// Catalog upkeep: create, rename, delete. Renaming and deleting need the
/// server's library-update-all permission, so a `*_own` user may get a 403 here
/// — that surfaces as the usual "not allowed" snack rather than a hidden button,
/// because the app cannot see the caller's permissions.
Future<void> showTagManageSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _TagManageSheet(),
    );

/// 409 is the catalog's duplicate-name answer, and the one status this screen
/// words better than the shared translator — which everything else falls
/// through to, so a refusal still names the permission it was refused for.
String _tagErr(AppApiException e, AppLocalizations l10n) =>
    e.statusCode == 409 ? l10n.fmTagExists : e.localized(l10n);

/// Shared behaviour of the four sheets: snacks, and creating a tag from a prompt.
mixin _TagSheetActions<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  AppLocalizations get l10n => AppLocalizations.of(context);

  void snack(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  /// Prompts for a name and creates the tag. Returns the new tag, or `null` when
  /// cancelled or refused.
  Future<LibraryTag?> createTag() async {
    final name = await promptName(
      context,
      title: l10n.fmTagNew,
      label: l10n.fmTagName,
      id: 'tag_new',
    );
    if (name == null || !mounted) return null;
    try {
      final tag = await ref.read(libraryRepositoryProvider).createTag(name);
      ref.invalidate(libraryTagsProvider);
      if (mounted) snack(l10n.fmTagCreated);
      return tag;
    } on AppApiException catch (e) {
      if (mounted) snack(_tagErr(e, l10n));
      return null;
    }
  }
}

/// The catalog list every sheet is built around: one checkbox per tag plus the
/// "new tag" row, or an empty state when the catalog is still bare.
class _TagList extends ConsumerWidget {
  const _TagList({
    required this.selected,
    required this.onToggle,
    required this.onCreate,
    required this.logId,
    this.showCounts = true,
  });

  final Set<int> selected;
  final ValueChanged<int> onToggle;
  final VoidCallback onCreate;

  /// Log area of the enclosing sheet (`tag_filter`, `file_tags`, `bulk_tags`).
  final String logId;

  final bool showCounts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(libraryTagsProvider);
    final tags = async.valueOrNull;

    if (async.isLoading && tags == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (async.hasError) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Text(l10n.connectFailed, textAlign: TextAlign.center),
      );
    }

    return Flexible(
      child: ListView(
        shrinkWrap: true,
        children: [
          if (tags == null || tags.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Text(l10n.fmTagsEmpty, textAlign: TextAlign.center),
            )
          else
            for (final tag in tags)
              CheckboxListTile(
                value: selected.contains(tag.id),
                onChanged: (_) => onToggle(tag.id),
                title: Text(tag.name),
                subtitle: showCounts && tag.fileCount > 0
                    ? Text(l10n.fmStatsFiles(tag.fileCount))
                    : null,
                controlAffinity: ListTileControlAffinity.leading,
              ).tagged('$logId.tag'),
          ListTile(
            leading: const Icon(Icons.new_label_outlined),
            title: Text(l10n.fmTagNew),
            onTap: onCreate,
          ).tagged('$logId.new'),
        ],
      ),
    );
  }
}

/// Sheet title row, with the catalog-upkeep shortcut on the right.
class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.title, this.onManage, this.subtitle});

  final String title;
  final String? subtitle;
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontFamily: DashTokens.fontUi,
                      fontSize: 11.5,
                      color: t.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onManage != null)
            logTag(
              'tag_filter.manage',
              IconButton(
                tooltip: AppLocalizations.of(context).fmTagsManage,
                icon: const Icon(Icons.tune),
                onPressed: onManage,
              ),
            ),
        ],
      ),
    );
  }
}

class _TagFilterSheet extends ConsumerStatefulWidget {
  const _TagFilterSheet();

  @override
  ConsumerState<_TagFilterSheet> createState() => _TagFilterSheetState();
}

class _TagFilterSheetState extends ConsumerState<_TagFilterSheet>
    with _TagSheetActions {
  late final Set<int> _selected = {
    ...?ref.read(fileManagerProvider).valueOrNull?.tagFilter,
  };

  void _apply(Set<int> tags) {
    ref.read(fileManagerProvider.notifier).setTagFilter(tags);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SheetHeader(
            title: l10n.fmTagsFilterTitle,
            subtitle: l10n.fmTagsFilterHint,
            onManage: () => showTagManageSheet(context),
          ),
          _TagList(
            selected: _selected,
            logId: 'tag_filter',
            onToggle: (id) => setState(() {
              _selected.contains(id) ? _selected.remove(id) : _selected.add(id);
            }),
            onCreate: () async {
              final tag = await createTag();
              if (tag != null && mounted) setState(() => _selected.add(tag.id));
            },
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                logTag(
                  'tag_filter.clear',
                  TextButton(
                    onPressed:
                        _selected.isEmpty ? null : () => _apply(const {}),
                    child: Text(l10n.clear),
                  ),
                ),
                const SizedBox(width: 8),
                logTag(
                  'tag_filter.apply',
                  FilledButton(
                    onPressed: () => _apply(_selected),
                    child: Text(l10n.fmTagsApply),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FileTagsSheet extends ConsumerStatefulWidget {
  const _FileTagsSheet({required this.file});

  final LibraryFile file;

  @override
  ConsumerState<_FileTagsSheet> createState() => _FileTagsSheetState();
}

class _FileTagsSheetState extends ConsumerState<_FileTagsSheet>
    with _TagSheetActions {
  late final Set<int> _selected = {for (final t in widget.file.tags) t.id};
  bool _saving = false;

  /// One file, so "the tags are exactly these" — `replace` says that in a single
  /// call, including the case where the user unticked everything.
  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(libraryRepositoryProvider).assignTags(
            fileIds: [widget.file.id],
            tagIds: _selected.toList(),
            action: TagAssignAction.replace,
          );
      ref.invalidate(libraryTagsProvider);
      if (!mounted) return;
      Navigator.pop(context, true);
    } on AppApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      snack(_tagErr(e, l10n));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SheetHeader(title: l10n.fmTags, subtitle: widget.file.displayName),
          _TagList(
            selected: _selected,
            logId: 'file_tags',
            showCounts: false,
            onToggle: (id) => setState(() {
              _selected.contains(id)
                  ? _selected.remove(id)
                  : _selected.add(id);
            }),
            onCreate: () async {
              final tag = await createTag();
              if (tag != null && mounted) {
                setState(() => _selected.add(tag.id));
              }
            },
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                logTag(
                  'file_tags.save',
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(l10n.fmSave),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BulkTagsSheet extends ConsumerStatefulWidget {
  const _BulkTagsSheet({required this.fileIds});

  final List<int> fileIds;

  @override
  ConsumerState<_BulkTagsSheet> createState() => _BulkTagsSheetState();
}

class _BulkTagsSheetState extends ConsumerState<_BulkTagsSheet>
    with _TagSheetActions {
  final Set<int> _selected = {};
  bool _saving = false;

  /// Three buttons rather than a mode selector plus one button: each action is
  /// then a control the log can name, and "replace" cannot be triggered by a
  /// mis-set radio the user forgot about.
  Future<void> _apply(TagAssignAction action) async {
    if (_selected.isEmpty && action != TagAssignAction.replace) {
      snack(l10n.fmTagsPickSome);
      return;
    }
    if (action == TagAssignAction.replace) {
      final ok = await confirmDialog(
        context,
        id: 'bulk_tags.replace_confirm',
        title: l10n.fmTagsReplace,
        message: l10n.fmTagsReplaceConfirm(widget.fileIds.length),
        confirmLabel: l10n.fmTagsReplace,
        destructive: true,
      );
      if (!ok || !mounted) return;
    }
    setState(() => _saving = true);
    try {
      final result = await ref.read(libraryRepositoryProvider).assignTags(
            fileIds: widget.fileIds,
            tagIds: _selected.toList(),
            action: action,
          );
      ref.invalidate(libraryTagsProvider);
      if (!mounted) return;
      // The server silently drops files the caller may not edit, so a count
      // short of what we sent is the only hint the user gets that their
      // permissions cut the operation down.
      final message = result.filesUpdated < widget.fileIds.length
          ? l10n.fmTagsPartial(result.filesUpdated, widget.fileIds.length)
          : l10n.fmTagsSaved;
      // Messenger resolved before the pop: looking it up afterwards means
      // walking a tree this sheet is already leaving.
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context, true);
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } on AppApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      snack(_tagErr(e, l10n));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SheetHeader(title: l10n.fmTagsBulkTitle(widget.fileIds.length)),
          _TagList(
            selected: _selected,
            logId: 'bulk_tags',
            onToggle: (id) => setState(() {
              _selected.contains(id)
                  ? _selected.remove(id)
                  : _selected.add(id);
            }),
            onCreate: () async {
              final tag = await createTag();
              if (tag != null && mounted) {
                setState(() => _selected.add(tag.id));
              }
            },
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                logTag(
                  'bulk_tags.replace',
                  TextButton(
                    onPressed:
                        _saving ? null : () => _apply(TagAssignAction.replace),
                    child: Text(l10n.fmTagsReplace),
                  ),
                ),
                const SizedBox(width: 4),
                logTag(
                  'bulk_tags.remove',
                  TextButton(
                    onPressed:
                        _saving ? null : () => _apply(TagAssignAction.remove),
                    child: Text(l10n.fmTagsRemove),
                  ),
                ),
                const SizedBox(width: 4),
                logTag(
                  'bulk_tags.add',
                  FilledButton(
                    onPressed:
                        _saving ? null : () => _apply(TagAssignAction.add),
                    child: Text(l10n.fmTagsAdd),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TagManageSheet extends ConsumerStatefulWidget {
  const _TagManageSheet();

  @override
  ConsumerState<_TagManageSheet> createState() => _TagManageSheetState();
}

class _TagManageSheetState extends ConsumerState<_TagManageSheet>
    with _TagSheetActions {
  Future<void> _rename(LibraryTag tag) async {
    final name = await promptName(
      context,
      title: l10n.fmTagRename,
      label: l10n.fmTagName,
      initial: tag.name,
      id: 'tag_rename',
    );
    if (name == null || name == tag.name || !mounted) return;
    try {
      await ref.read(libraryRepositoryProvider).renameTag(tag.id, name);
      ref.invalidate(libraryTagsProvider);
      // Tag names travel inside the file listing, so the visible chips are stale
      // until the files are re-read.
      await ref.read(fileManagerProvider.notifier).refresh();
      if (mounted) snack(l10n.fmRenamed);
    } on AppApiException catch (e) {
      if (mounted) snack(_tagErr(e, l10n));
    }
  }

  Future<void> _delete(LibraryTag tag) async {
    final ok = await confirmDialog(
      context,
      id: 'tag_manage.delete_confirm',
      title: l10n.fmTagDelete,
      message: l10n.fmTagDeleteConfirm(tag.name),
      confirmLabel: l10n.fmDelete,
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(libraryRepositoryProvider).deleteTag(tag.id);
      ref.invalidate(libraryTagsProvider);
      // A deleted tag may be the one being filtered by — drop it from the
      // filter, otherwise the listing keeps asking for an id that is gone.
      final notifier = ref.read(fileManagerProvider.notifier);
      final filter = ref.read(fileManagerProvider).valueOrNull?.tagFilter;
      if (filter != null && filter.contains(tag.id)) {
        await notifier.setTagFilter(filter.difference({tag.id}));
      } else {
        await notifier.refresh();
      }
      if (mounted) snack(l10n.fmTagDeleted);
    } on AppApiException catch (e) {
      if (mounted) snack(_tagErr(e, l10n));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(libraryTagsProvider);
    final tags = async.valueOrNull ?? const <LibraryTag>[];
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SheetHeader(title: l10n.fmTagsManage),
          if (async.isLoading && async.valueOrNull == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  if (tags.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 16),
                      child:
                          Text(l10n.fmTagsEmpty, textAlign: TextAlign.center),
                    )
                  else
                    for (final tag in tags)
                      ListTile(
                        leading: const Icon(Icons.sell_outlined),
                        title: Text(tag.name),
                        subtitle: tag.fileCount > 0
                            ? Text(l10n.fmStatsFiles(tag.fileCount))
                            : null,
                        trailing: logTag(
                          'tag_manage.actions',
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert),
                            onSelected: (v) =>
                                v == 'rename' ? _rename(tag) : _delete(tag),
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'rename',
                                child: logTag('tag_manage.rename',
                                    Text(l10n.fmRename)),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: logTag('tag_manage.delete',
                                    Text(l10n.fmDelete)),
                              ),
                            ],
                          ),
                        ),
                      ).tagged('tag_manage.tag'),
                  ListTile(
                    leading: const Icon(Icons.new_label_outlined),
                    title: Text(l10n.fmTagNew),
                    onTap: createTag,
                  ).tagged('tag_manage.new'),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
