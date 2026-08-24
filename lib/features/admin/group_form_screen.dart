import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diagnostics/log_tag.dart';
import '../../core/models/group_summary.dart';
import '../../core/models/group_write.dart';
import '../../core/models/permission_catalog.dart';
import '../../core/theme/dash_text.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common/dash_async.dart';
import '../common/dash_snack.dart';
import '../common/system_insets.dart';
import 'groups_providers.dart';
import 'user_messages.dart';
import 'users_providers.dart';

/// Create / edit a group — a name, what it is for, and the permissions it
/// grants. This is where "print, but do not delete archives" is written down.
///
/// A system group is opened read-only apart from its description: the server
/// refuses to rename one or to change what it grants
/// (`backend/app/api/routes/groups.py::update_group`, `:200`), so the fields
/// are shown disabled instead of accepting input that would come back a 400.
class GroupFormScreen extends ConsumerStatefulWidget {
  const GroupFormScreen({super.key, this.existing});

  final GroupSummary? existing;

  bool get isEdit => existing != null;

  @override
  ConsumerState<GroupFormScreen> createState() => _GroupFormScreenState();
}

class _GroupFormScreenState extends ConsumerState<GroupFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _description;

  /// Everything the group grants — including permissions in categories the
  /// editor keeps folded away. `PATCH` replaces the whole set, so what is not
  /// on screen still has to be in here or saving would revoke it.
  late Set<String> _permissions;

  bool _showAdvanced = false;
  bool _saving = false;

  bool get _locked => widget.existing?.isSystem ?? false;

  @override
  void initState() {
    super.initState();
    final g = widget.existing;
    _name = TextEditingController(text: g?.name ?? '');
    _description = TextEditingController(text: g?.description ?? '');
    _permissions = {...?g?.permissions};
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final catalog = ref.watch(permissionCatalogProvider);
    final fieldStyle = t.bodyStrong;

    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: dashAppBar(
          context,
          title: widget.isEdit ? l10n.groupsEditTitle : l10n.groupsCreateTitle,
          actions: [
            TextButton(
              style: TextButton.styleFrom(foregroundColor: t.accentGreenInk),
              onPressed: _saving ? null : _submit,
              child: Text(l10n.usersSave),
            ).tagged('group_form.save'),
          ],
        ),
        body: AbsorbPointer(
          absorbing: _saving,
          child: Form(
            key: _formKey,
            child: ListView(
              padding: withSystemNavInset(
                context,
                const EdgeInsets.fromLTRB(16, 12, 16, 32),
              ),
              children: [
                if (_locked) ...[
                  _LockedNotice(text: l10n.groupsSystemFormNote),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _name,
                  style: fieldStyle,
                  enabled: !_locked,
                  decoration:
                      dashFieldDecoration(t, labelText: l10n.groupsFieldName),
                  textInputAction: TextInputAction.next,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? l10n.usersFieldRequired
                      : null,
                ).tagged('group_form.name'),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _description,
                  style: fieldStyle,
                  decoration: dashFieldDecoration(
                    t,
                    labelText: l10n.groupsFieldDescription,
                  ),
                  maxLines: 2,
                ).tagged('group_form.description'),
                const SizedBox(height: 20),
                dashAsync(
                  context,
                  catalog,
                  onRetry: () => ref.invalidate(permissionCatalogProvider),
                  errorIcon: null,
                  skipLoadingOnReload: false,
                  skipLoadingOnRefresh: false,
                  data: _permissionEditor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _permissionEditor(PermissionCatalog catalog) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final advanced = catalog.advanced;
    // Permissions this group holds inside the folded-away categories. Worth
    // stating: they are what saving would silently carry along, and someone
    // auditing a group needs to know they exist.
    final advancedSelected = advanced
        .expand((c) => c.permissions)
        .where((p) => _permissions.contains(p.value))
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.groupsPermissionsHeader,
                style: t.bodyBold.copyWith(letterSpacing: 0.3),
              ),
            ),
            Text(
              l10n.groupsPermissionsSelected(_permissions.length),
              style: t.monoLabel,
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final category in catalog.everyday)
          _CategoryTile(
            category: category,
            selected: _permissions,
            enabled: !_locked,
            onToggle: _toggle,
            onToggleAll: _toggleCategory,
          ),
        if (advanced.isNotEmpty) ...[
          const SizedBox(height: 8),
          logTag(
            'group_form.advanced',
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => setState(() => _showAdvanced = !_showAdvanced),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                child: Row(
                  children: [
                    Icon(
                      _showAdvanced ? Icons.expand_less : Icons.expand_more,
                      size: 20,
                      color: t.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.groupsAdvancedPermissions,
                        style: t.bodyBold.copyWith(color: t.textPrimary),
                      ),
                    ),
                    if (advancedSelected > 0)
                      DashPill(
                        label: '$advancedSelected',
                        accent: t.accentOrange,
                      ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              l10n.groupsAdvancedHint,
              style: t.microSoft,
            ),
          ),
          if (_showAdvanced)
            for (final category in advanced)
              _CategoryTile(
                category: category,
                selected: _permissions,
                enabled: !_locked,
                onToggle: _toggle,
                onToggleAll: _toggleCategory,
              ),
        ],
      ],
    );
  }

  void _toggle(String permission, bool on) => setState(() {
        on ? _permissions.add(permission) : _permissions.remove(permission);
      });

  void _toggleCategory(PermissionCategory category, bool on) => setState(() {
        for (final p in category.permissions) {
          on ? _permissions.add(p.value) : _permissions.remove(p.value);
        }
      });

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final repo = ref.read(groupsRepositoryProvider);
    final existing = widget.existing;
    setState(() => _saving = true);

    final name = _name.text.trim();
    final description = _description.text.trim();
    final permissions = _permissions.toList()..sort();

    final result = await runUserWrite(() async {
      if (existing == null) {
        await repo.create(GroupCreateInput(
          name: name,
          description: description.isEmpty ? null : description,
          permissions: permissions,
        ));
        return;
      }
      final body = GroupUpdateInput(
        name: _locked || name == existing.name ? null : name,
        description:
            description == (existing.description ?? '') ? null : description,
        // Sending the set of a system group is refused outright, and it cannot
        // have changed anyway — the editor was disabled.
        permissions: _locked || _samePermissions(existing.permissions)
            ? null
            : permissions,
      );
      if (body.isEmpty) return;
      await repo.update(existing.id, body);
    }, 'group_form.save');

    ref.invalidate(groupsListProvider);
    if (existing != null) {
      ref.invalidate(groupDetailProvider(existing.id));
    }
    // What a group grants is where a member's permissions come from — your own
    // included.
    await ref.read(currentUserProvider.notifier).refresh();
    ref.invalidate(usersListProvider);
    if (!mounted) return;
    setState(() => _saving = false);

    messenger.snack(result.ok ? l10n.groupsSaved : userWriteMessage(l10n, result));
    if (result.ok) navigator.pop();
  }

  bool _samePermissions(List<String> current) {
    if (current.length != _permissions.length) return false;
    return _permissions.containsAll(current);
  }
}

/// One category: a header that selects or clears the lot, and a row per
/// permission. Collapsed by default — sixty checkboxes at once is not a phone
/// screen.
class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.selected,
    required this.enabled,
    required this.onToggle,
    required this.onToggleAll,
  });

  final PermissionCategory category;
  final Set<String> selected;
  final bool enabled;
  final void Function(String permission, bool selected) onToggle;
  final void Function(PermissionCategory category, bool selected) onToggleAll;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final count =
        category.permissions.where((p) => selected.contains(p.value)).length;
    final all = count == category.permissions.length;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      // Material, not a decorated box: the tile's ripple paints on the nearest
      // Material ancestor, and a coloured box in between would hide it.
      child: Material(
        color: t.subCard,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: count > 0 ? t.accentGreen.withValues(alpha: 0.3) : t.subCardBorder,
          ),
        ),
        child: Theme(
          // The stock divider on an ExpansionTile fights the card border.
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 12),
            childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    category.name,
                    style: t.titleSm,
                  ),
                ),
                Text(
                  '$count/${category.permissions.length}',
                  style: t.monoLabel.copyWith(color: count > 0 ? t.accentGreenInk : t.textTertiary),
                ),
                Checkbox(
                  value: all,
                  // Neither fully on nor fully off: the header still selects
                  // everything, and shows that some of it already is.
                  tristate: false,
                  onChanged: enabled
                      ? (v) => onToggleAll(category, v ?? false)
                      : null,
                ).tagged('group_form.category_all'),
              ],
            ),
            children: [
              for (final p in category.permissions)
                CheckboxListTile(
                  value: selected.contains(p.value),
                  onChanged:
                      enabled ? (v) => onToggle(p.value, v ?? false) : null,
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: Text(
                    p.label,
                    style: t.body,
                  ),
                  subtitle: Text(
                    p.value,
                    style: t.monoMicro,
                  ),
                ).tagged('group_form.permission'),
            ],
          ).tagged('group_form.category'),
        ),
      ),
    );
  }
}

class _LockedNotice extends StatelessWidget {
  const _LockedNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: t.accentOrange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.accentOrange.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, size: 18, color: t.accentOrange),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: t.label.copyWith(color: t.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Imperative entry: create a group.
Future<void> openGroupCreate(BuildContext context) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const GroupFormScreen()),
    );

/// Imperative entry: edit [group].
Future<void> openGroupEdit(BuildContext context, GroupSummary group) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => GroupFormScreen(existing: group)),
    );
