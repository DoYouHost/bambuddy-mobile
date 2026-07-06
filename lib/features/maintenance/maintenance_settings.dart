import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/maintenance.dart';
import '../../l10n/app_localizations.dart';
import '../common/confirm_dialog.dart';
import 'maintenance_icons.dart';
import 'maintenance_providers.dart';

/// Shows a SnackBar for a maintenance action result.
void showMaintenanceResult(
  BuildContext context,
  AppLocalizations l10n,
  MaintenanceActionResult result,
) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(switch (result) {
        MaintenanceActionResult.ok => l10n.maintenanceSaved,
        MaintenanceActionResult.forbidden => l10n.errForbidden,
        MaintenanceActionResult.error => l10n.maintenanceFailed,
      }),
    ),
  );
}

/// Maintenance settings screen (pushed from the Status screen's gear action).
/// Everything configurable lives here: manage maintenance types (create / edit
/// / delete / restore defaults) and, per printer, mute tasks and override their
/// intervals. The Status screen stays view-only (preview + mark done + history).
class MaintenanceSettingsScreen extends ConsumerWidget {
  const MaintenanceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final typesAsync = ref.watch(maintenanceTypesProvider);
    final overview =
        ref.watch(maintenanceOverviewProvider).valueOrNull ?? const [];

    return Scaffold(
      appBar: AppBar(title: Text(l10n.maintenanceSettingsTitle)),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(maintenanceTypesProvider.notifier).refresh();
          await ref.read(maintenanceOverviewProvider.notifier).refresh();
        },
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            // --- Maintenance types ---
            _SectionHeader(
              title: l10n.maintenanceTypesTitle,
              subtitle: l10n.maintenanceTypesSubtitle,
              trailing: Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _restoreDefaults(context, ref, l10n),
                    icon: const Icon(Icons.restart_alt),
                    label: Text(l10n.maintenanceRestoreDefaults),
                  ),
                  FilledButton.icon(
                    onPressed: () => openTypeForm(context),
                    icon: const Icon(Icons.add),
                    label: Text(l10n.maintenanceAddType),
                  ),
                ],
              ),
            ),
            typesAsync.when(
              skipLoadingOnReload: true,
              skipLoadingOnRefresh: true,
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text(l10n.connectFailed),
              ),
              data: (types) => Column(
                children: [for (final t in types) _TypeTile(type: t)],
              ),
            ),

            // --- Per-printer interval overrides + mute ---
            if (overview.isNotEmpty) ...[
              const Divider(height: 24),
              _SectionHeader(
                title: l10n.maintenanceOverridesTitle,
                subtitle: l10n.maintenanceOverridesSubtitle,
              ),
              for (final printer in overview) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    printer.printerName,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                for (final item in printer.maintenanceItems)
                  _OverrideTile(item: item),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _restoreDefaults(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final ok = await confirmDialog(
      context,
      title: l10n.maintenanceRestoreDefaults,
      message: l10n.maintenanceRestoreConfirm,
      confirmLabel: l10n.maintenanceRestoreDefaults,
    );
    if (!ok || !context.mounted) return;
    final result =
        await ref.read(maintenanceTypesProvider.notifier).restoreDefaults();
    if (!context.mounted) return;
    showMaintenanceResult(context, l10n, result);
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          Text(subtitle, style: theme.textTheme.bodySmall),
          if (trailing != null) ...[const SizedBox(height: 8), trailing!],
        ],
      ),
    );
  }
}

/// A maintenance type row (tap to edit, trash to delete).
class _TypeTile extends ConsumerWidget {
  const _TypeTile({required this.type});

  final MaintenanceType type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        child: Icon(maintenanceIcon(type.icon), size: 20),
      ),
      title: Text(type.name),
      subtitle: Text(
        [
          type.isDays
              ? l10n.maintenanceEveryDays(type.defaultIntervalHours.round())
              : l10n.maintenanceEveryHours(type.defaultIntervalHours.round()),
          if (type.isSystem) l10n.maintenanceSystemType,
        ].join(' · '),
      ),
      onTap: () => openTypeForm(context, existing: type),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: l10n.inventoryDelete,
        onPressed: () => _delete(context, ref, l10n),
      ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final ok = await confirmDialog(
      context,
      title: l10n.maintenanceDeleteTypeTitle,
      // System types are only hidden (restorable); custom ones are removed.
      message: type.isSystem
          ? l10n.maintenanceHideTypeConfirm(type.name)
          : l10n.maintenanceDeleteTypeConfirm(type.name),
      confirmLabel: l10n.inventoryDelete,
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    final result =
        await ref.read(maintenanceTypesProvider.notifier).delete(type.id);
    if (!context.mounted) return;
    showMaintenanceResult(context, l10n, result);
  }
}

/// Per-printer maintenance item row: mute toggle + interval override editor.
class _OverrideTile extends ConsumerWidget {
  const _OverrideTile({required this.item});

  final MaintenanceStatus item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final unit = item.intervalType == 'days'
        ? l10n.maintenanceEveryDays(item.intervalHours.round())
        : l10n.maintenanceEveryHours(item.intervalHours.round());
    return Opacity(
      opacity: item.enabled ? 1 : 0.5,
      child: ListTile(
        dense: true,
        leading: Icon(maintenanceIcon(item.maintenanceTypeIcon)),
        title: Text(item.maintenanceTypeName),
        subtitle: Text(unit),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                item.enabled
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_off_outlined,
              ),
              tooltip: item.enabled ? l10n.maintenanceMute : l10n.maintenanceUnmute,
              onPressed: () => _toggleMute(context, ref, l10n),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: l10n.maintenanceEditInterval,
              onPressed: () => _editInterval(context, ref, l10n),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleMute(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref
        .read(maintenanceOverviewProvider.notifier)
        .setEnabled(item.id, !item.enabled);
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(switch (result) {
      MaintenanceActionResult.ok =>
        item.enabled ? l10n.maintenanceMuted : l10n.maintenanceUnmuted,
      MaintenanceActionResult.forbidden => l10n.errForbidden,
      MaintenanceActionResult.error => l10n.maintenanceFailed,
    })));
  }

  Future<void> _editInterval(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final outcome = await showDialog<_IntervalOutcome>(
      context: context,
      builder: (_) => _IntervalEditDialog(item: item),
    );
    if (outcome == null || !context.mounted) return;
    final result = await ref
        .read(maintenanceOverviewProvider.notifier)
        .setInterval(item.id, outcome.reset ? null : outcome.hours);
    if (!context.mounted) return;
    showMaintenanceResult(context, l10n, result);
  }
}

/// Opens the create/edit type sheet. [existing] != null → edit mode.
void openTypeForm(BuildContext context, {MaintenanceType? existing}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _TypeFormSheet(existing: existing),
  );
}

class _TypeFormSheet extends ConsumerStatefulWidget {
  const _TypeFormSheet({this.existing});

  final MaintenanceType? existing;

  @override
  ConsumerState<_TypeFormSheet> createState() => _TypeFormSheetState();
}

class _TypeFormSheetState extends ConsumerState<_TypeFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _interval;
  late final TextEditingController _wiki;
  late String _intervalType;
  String? _icon;
  final _printers = <int>{};
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final t = widget.existing;
    _name = TextEditingController(text: t?.name ?? '');
    _interval = TextEditingController(
      text: (t?.defaultIntervalHours ?? 100).round().toString(),
    );
    _wiki = TextEditingController(text: t?.wikiUrl ?? '');
    _intervalType = t?.intervalType ?? 'hours';
    _icon = t?.icon ?? maintenanceIconNames.first;
  }

  @override
  void dispose() {
    _name.dispose();
    _interval.dispose();
    _wiki.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    // Custom types only appear on printers they're assigned to (create only).
    if (!_isEdit && _availablePrinters().isNotEmpty && _printers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.maintenanceSelectPrinter)),
      );
      return;
    }
    final draft = MaintenanceTypeDraft(
      name: _name.text.trim(),
      defaultIntervalHours: double.tryParse(_interval.text.trim()),
      intervalType: _intervalType,
      icon: _icon,
      wikiUrl: _wiki.text.trim().isEmpty ? null : _wiki.text.trim(),
    );
    setState(() => _saving = true);
    final notifier = ref.read(maintenanceTypesProvider.notifier);
    final result = _isEdit
        ? await notifier.editType(widget.existing!.id, draft)
        : await notifier.create(draft, _printers.toList());
    if (!mounted) return;
    if (result == MaintenanceActionResult.ok) {
      Navigator.of(context).pop();
      showMaintenanceResult(context, l10n, result);
    } else {
      setState(() => _saving = false);
      showMaintenanceResult(context, l10n, result);
    }
  }

  /// Printers available as assignment targets, from the loaded status overview.
  List<({int id, String name})> _availablePrinters() {
    final overview =
        ref.read(maintenanceOverviewProvider).valueOrNull ?? const [];
    return [for (final p in overview) (id: p.printerId, name: p.printerName)];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final printers = _availablePrinters();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (context, controller) => Form(
        key: _formKey,
        child: ListView(
          controller: controller,
          padding: EdgeInsets.fromLTRB(16, 0, 16, 24 + bottomInset),
          children: [
            Text(
              _isEdit ? l10n.maintenanceEditType : l10n.maintenanceAddType,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: l10n.maintenanceFieldName,
                hintText: l10n.maintenanceFieldNameHint,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              validator: (v) => (v ?? '').trim().isEmpty
                  ? l10n.inventoryFieldRequired
                  : null,
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _intervalType,
                    decoration: InputDecoration(
                      labelText: l10n.maintenanceFieldIntervalType,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'hours',
                        child: Text(l10n.maintenanceIntervalHours),
                      ),
                      DropdownMenuItem(
                        value: 'days',
                        child: Text(l10n.maintenanceIntervalDays),
                      ),
                    ],
                    onChanged: (v) =>
                        setState(() => _intervalType = v ?? 'hours'),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 110,
                  child: TextFormField(
                    controller: _interval,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: l10n.maintenanceFieldInterval,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    validator: (v) {
                      final n = double.tryParse((v ?? '').trim());
                      if (n == null || n < 1) {
                        return l10n.maintenanceIntervalInvalid;
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(l10n.maintenanceFieldIcon, style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final name in maintenanceIconNames)
                  _IconChoice(
                    icon: maintenanceIcon(name),
                    selected: _icon == name,
                    onTap: () => setState(() => _icon = name),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _wiki,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: l10n.maintenanceFieldDocLink,
                hintText: 'https://…',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (!_isEdit && printers.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                l10n.maintenanceAssignPrinters,
                style: theme.textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in printers)
                    FilterChip(
                      label: Text(p.name),
                      selected: _printers.contains(p.id),
                      onSelected: (sel) => setState(() {
                        if (sel) {
                          _printers.add(p.id);
                        } else {
                          _printers.remove(p.id);
                        }
                      }),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.inventorySave),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconChoice extends StatelessWidget {
  const _IconChoice({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: selected
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Icon(
          icon,
          size: 22,
          color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Outcome of the interval-edit dialog: a new [hours] override, or [reset] to
/// clear the override back to the type default. Null (dismissed) = no-op.
class _IntervalOutcome {
  const _IntervalOutcome({this.hours, this.reset = false});

  final double? hours;
  final bool reset;
}

/// Per-printer interval override editor. Prefilled with the current effective
/// interval; "Reset" clears the override (back to the type default).
class _IntervalEditDialog extends StatefulWidget {
  const _IntervalEditDialog({required this.item});

  final MaintenanceStatus item;

  @override
  State<_IntervalEditDialog> createState() => _IntervalEditDialogState();
}

class _IntervalEditDialogState extends State<_IntervalEditDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.item.intervalHours.round().toString(),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final unit = widget.item.intervalType == 'days'
        ? l10n.maintenanceIntervalDays
        : l10n.maintenanceIntervalHours;
    return AlertDialog(
      title: Text(l10n.maintenanceEditInterval),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.item.maintenanceTypeName),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: unit,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.pop(context, const _IntervalOutcome(reset: true)),
          child: Text(l10n.maintenanceResetInterval),
        ),
        const Spacer(),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () {
            final v = double.tryParse(_controller.text.trim());
            if (v == null || v < 1) return;
            Navigator.pop(context, _IntervalOutcome(hours: v));
          },
          child: Text(l10n.inventorySave),
        ),
      ],
    );
  }
}
