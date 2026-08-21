import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/action_outcome.dart';
import '../../core/diagnostics/log_tag.dart';
import '../../core/models/maintenance.dart';
import '../../core/theme/dash_text.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import '../common/confirm_dialog.dart';
import '../common/dash_async.dart';
import '../common/dash_progress.dart';
import '../common/dash_sheet.dart';
import '../common/dash_snack.dart';
import '../common/system_insets.dart';
import 'maintenance_icons.dart';
import 'maintenance_providers.dart';

/// Shows a SnackBar for a maintenance action: the shared reason when it
/// failed, this screen's own confirmation when it did not.
void showMaintenanceResult(
  BuildContext context,
  AppLocalizations l10n,
  ActionOutcome result,
) {
  ScaffoldMessenger.of(context).snack(result.messageFor(l10n) ?? l10n.maintenanceSaved);
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
    final t = DashTokens.of(context);
    final typesAsync = ref.watch(maintenanceTypesProvider);
    final overview =
        ref.watch(maintenanceOverviewProvider).valueOrNull ?? const [];

    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: dashAppBar(context, title: l10n.maintenanceSettingsTitle),
        body: RefreshIndicator(
          onRefresh: () async {
            await ref.read(maintenanceTypesProvider.notifier).refresh();
            await ref.read(maintenanceOverviewProvider.notifier).refresh();
          },
          child: ListView(
            padding: withSystemNavInset(
              context,
              const EdgeInsets.fromLTRB(16, 8, 16, 24),
            ),
            children: [
              // --- Maintenance types ---
              _SectionHeader(
                title: l10n.maintenanceTypesTitle,
                subtitle: l10n.maintenanceTypesSubtitle,
                trailing: Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: t.textPrimary,
                        side: BorderSide(color: t.cardBorder),
                      ),
                      onPressed: () => _restoreDefaults(context, ref, l10n),
                      icon: const Icon(Icons.restart_alt),
                      label: Text(l10n.maintenanceRestoreDefaults),
                    ).tagged('maintenance_settings.restore_defaults'),
                    FilledButton.icon(
                      style: dashPrimaryButtonStyle(t),
                      onPressed: () => openTypeForm(context),
                      icon: const Icon(Icons.add),
                      label: Text(l10n.maintenanceAddType),
                    ).tagged('maintenance_settings.add_type'),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              dashAsyncStrip(
                context,
                typesAsync,
                data: (types) => _DashCard(
                  children: [for (final ty in types) _TypeTile(type: ty)],
                ),
              ),

              // --- Per-printer interval overrides + mute ---
              if (overview.isNotEmpty) ...[
                const SizedBox(height: 20),
                _SectionHeader(
                  title: l10n.maintenanceOverridesTitle,
                  subtitle: l10n.maintenanceOverridesSubtitle,
                ),
                const SizedBox(height: 8),
                for (final printer in overview) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                    child: Text(
                      printer.printerName,
                      style: t.bodyBold.copyWith(color: t.accentGreenInk),
                    ),
                  ),
                  _DashCard(
                    children: [
                      for (final item in printer.maintenanceItems)
                        _OverrideTile(item: item),
                    ],
                  ),
                ],
              ],
            ],
          ),
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
      id: 'maintenance.restore_defaults_confirm',
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
    final t = DashTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: t.titleMd,
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: t.label,
        ),
        if (trailing != null) ...[const SizedBox(height: 10), trailing!],
      ],
    );
  }
}

/// Card grouping related rows — same container styling as the maintenance
/// screen's printer cards.
class _DashCard extends StatelessWidget {
  const _DashCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        gradient: t.cardGradient,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: t.cardBorder),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(height: 1, indent: 12, endIndent: 12, color: t.hairline),
            children[i],
          ],
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
    final t = DashTokens.of(context);
    return ListTile(
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: t.accentGreen.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(maintenanceIcon(type.icon), size: 18, color: t.accentGreenInk),
      ),
      title: Text(
        type.name,
        style: t.titleSm,
      ),
      subtitle: Text(
        [
          type.isDays
              ? l10n.maintenanceEveryDays(type.defaultIntervalHours.round())
              : l10n.maintenanceEveryHours(type.defaultIntervalHours.round()),
          if (type.isSystem) l10n.maintenanceSystemType,
        ].join(' · '),
        style: t.label,
      ),
      onTap: () => openTypeForm(context, existing: type),
      trailing: IconButton(
        icon: Icon(Icons.delete_outline, color: t.textSecondary),
        tooltip: l10n.inventoryDelete,
        onPressed: () => _delete(context, ref, l10n),
      ).tagged('maintenance_settings.delete_type'),
    ).tagged('maintenance_settings.type');
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final ok = await confirmDialog(
      context,
      id: 'maintenance.delete_type_confirm',
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
    final t = DashTokens.of(context);
    final unit = item.intervalType == 'days'
        ? l10n.maintenanceEveryDays(item.intervalHours.round())
        : l10n.maintenanceEveryHours(item.intervalHours.round());
    return Opacity(
      opacity: item.enabled ? 1 : 0.5,
      child: ListTile(
        dense: true,
        leading: Icon(maintenanceIcon(item.maintenanceTypeIcon),
            color: t.textSecondary),
        title: Text(
          item.maintenanceTypeName,
          style: t.titleSm,
        ),
        subtitle: Text(
          unit,
          style: t.monoLabel,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                item.enabled
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_off_outlined,
                color: t.textSecondary,
              ),
              tooltip: item.enabled ? l10n.maintenanceMute : l10n.maintenanceUnmute,
              onPressed: () => _toggleMute(context, ref, l10n),
            ).tagged('maintenance_settings.mute'),
            IconButton(
              icon: Icon(Icons.edit_outlined, color: t.textSecondary),
              tooltip: l10n.maintenanceEditInterval,
              onPressed: () => _editInterval(context, ref, l10n),
            ).tagged('maintenance_settings.interval'),
          ],
        ),
      ).tagged('maintenance_settings.override'),
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
    messenger.snack(result.messageFor(l10n) ??
            (item.enabled ? l10n.maintenanceMuted : l10n.maintenanceUnmuted));
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
  dashSheet<void>(
    context,
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
      ScaffoldMessenger.of(context).snack(l10n.maintenanceSelectPrinter);
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
    if (result.isOk) {
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
            ).tagged('maintenance_type_form.name'),
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
                        child: logTag(
                            'maintenance_type_form.interval_type.hours',
                            Text(l10n.maintenanceIntervalHours)),
                      ),
                      DropdownMenuItem(
                        value: 'days',
                        child: logTag(
                            'maintenance_type_form.interval_type.days',
                            Text(l10n.maintenanceIntervalDays)),
                      ),
                    ],
                    onChanged: (v) =>
                        setState(() => _intervalType = v ?? 'hours'),
                  ).tagged('maintenance_type_form.interval_type'),
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
                  ).tagged('maintenance_type_form.interval'),
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
            ).tagged('maintenance_type_form.description'),
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
                    ).tagged('maintenance_type_form.printer'),
                ],
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const DashSpinner(size: 20)
                  : Text(l10n.inventorySave),
            ).tagged('maintenance_type_form.save'),
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
    ).tagged('maintenance_type_form.icon');
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
          ).tagged('interval_edit.value'),
        ],
      ),
      actions: [
        logTag(
          'interval_edit.reset',
          TextButton(
            onPressed: () =>
                Navigator.pop(context, const _IntervalOutcome(reset: true)),
            child: Text(l10n.maintenanceResetInterval),
          ),
        ),
        const Spacer(),
        logTag(
          'interval_edit.cancel',
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
        ),
        logTag(
          'interval_edit.save',
          FilledButton(
            onPressed: () {
              final v = double.tryParse(_controller.text.trim());
              if (v == null || v < 1) return;
              Navigator.pop(context, _IntervalOutcome(hours: v));
            },
            child: Text(l10n.inventorySave),
          ),
        ),
      ],
    );
  }
}
