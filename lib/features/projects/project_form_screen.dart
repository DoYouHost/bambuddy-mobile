import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/action_outcome.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/diagnostics/log_tag.dart';
import '../../core/format/datetime_format.dart';
import '../../core/models/json_utils.dart';
import '../../core/models/project.dart';
import '../../core/theme/dash_text.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import '../../providers.dart';
import '../common/dash_snack.dart';
import '../common/system_insets.dart';
import 'project_common.dart';
import 'projects_providers.dart';

/// Create / edit project form. When [existing] is null it creates (POST);
/// otherwise it edits via PATCH and prefills from the project.
class ProjectFormScreen extends ConsumerStatefulWidget {
  const ProjectFormScreen({super.key, this.existing});

  final ProjectResponse? existing;

  bool get isEdit => existing != null;

  @override
  ConsumerState<ProjectFormScreen> createState() => _ProjectFormScreenState();
}

class _ProjectFormScreenState extends ConsumerState<ProjectFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _notes;
  late final TextEditingController _tags;
  late final TextEditingController _url;
  late final TextEditingController _targetCount;
  late final TextEditingController _targetSets;
  late final TextEditingController _targetParts;
  late final TextEditingController _budget;

  late String _status;
  late String _priority;
  String? _color;
  DateTime? _dueDate;
  int? _parentId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _name = TextEditingController(text: p?.name ?? '');
    _description = TextEditingController(text: p?.description ?? '');
    _notes = TextEditingController(text: p?.notes ?? '');
    _tags = TextEditingController(text: p?.tags ?? '');
    _url = TextEditingController(text: p?.url ?? '');
    _targetCount =
        TextEditingController(text: p?.targetCount?.toString() ?? '');
    _targetParts =
        TextEditingController(text: p?.targetPartsCount?.toString() ?? '');
    _targetSets = TextEditingController(text: p?.targetSets?.toString() ?? '');
    _budget = TextEditingController(text: p?.budget?.toString() ?? '');
    _status = p?.status ?? 'active';
    _priority = p?.priority ?? 'normal';
    _color = p?.color;
    _dueDate = p?.dueDateParsed;
    _parentId = p?.parentId;
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _description,
      _notes,
      _tags,
      _url,
      _targetCount,
      _targetParts,
      _targetSets,
      _budget,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final fieldStyle = t.bodyStrong;
    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: dashAppBar(
          context,
          title: widget.isEdit ? l10n.projectEdit : l10n.projectCreate,
          actions: [
            TextButton(
              style: TextButton.styleFrom(foregroundColor: t.accentGreenInk),
              onPressed: _saving ? null : _submit,
              child: Text(l10n.projectSave),
            ).tagged('project_form.save'),
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
                TextFormField(
                  controller: _name,
                  style: fieldStyle,
                  decoration: dashFieldDecoration(t, labelText: l10n.projectName),
                  textInputAction: TextInputAction.next,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? l10n.projectNameRequired
                      : null,
                ).tagged('project_form.name'),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _description,
                  style: fieldStyle,
                  decoration:
                      dashFieldDecoration(t, labelText: l10n.projectDescription),
                  maxLines: 2,
                ).tagged('project_form.description'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _status,
                        style: fieldStyle,
                        dropdownColor: t.isDark ? const Color(0xFF141A13) : Colors.white,
                        decoration:
                            dashFieldDecoration(t, labelText: l10n.projectStatus),
                        items: [
                          // Named per value — a fixed server-side list, and
                          // which status was set is the record.
                          for (final s in projectStatusValues)
                            DropdownMenuItem(
                              value: s,
                              child: logTag('project_form.status.$s',
                                  Text(projectStatusLabel(l10n, s))),
                            ),
                        ],
                        onChanged: (v) => setState(() => _status = v ?? _status),
                      ).tagged('project_form.status'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _priority,
                        style: fieldStyle,
                        dropdownColor: t.isDark ? const Color(0xFF141A13) : Colors.white,
                        decoration:
                            dashFieldDecoration(t, labelText: l10n.projectPriority),
                        items: [
                          for (final s in projectPriorityValues)
                            DropdownMenuItem(
                              value: s,
                              child: logTag('project_form.priority.$s',
                                  Text(projectPriorityLabel(l10n, s))),
                            ),
                        ],
                        onChanged: (v) => setState(() => _priority = v ?? _priority),
                      ).tagged('project_form.priority'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _colorRow(l10n, t),
                const SizedBox(height: 16),
                _dueDateRow(l10n, t),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _targetCount,
                        style: fieldStyle,
                        decoration: dashFieldDecoration(t,
                            labelText: l10n.projectTargetCount),
                        keyboardType: TextInputType.number,
                      ).tagged('project_form.target_count'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _targetParts,
                        style: fieldStyle,
                        decoration: dashFieldDecoration(t,
                            labelText: l10n.projectTargetPartsCount),
                        keyboardType: TextInputType.number,
                      ).tagged('project_form.target_parts'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Sets are a 1.2.5.2 column. An older server ignores the field
                // rather than failing, so the input stays offered instead of
                // being gated behind a version probe — but nothing reads it
                // back, so the value simply won't stick there.
                TextFormField(
                  controller: _targetSets,
                  style: fieldStyle,
                  decoration: dashFieldDecoration(t,
                      labelText: l10n.projectTargetSets,
                      helperText: l10n.projectTargetSetsHint),
                  keyboardType: TextInputType.number,
                ).tagged('project_form.target_sets'),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _budget,
                  style: fieldStyle,
                  decoration: dashFieldDecoration(t, labelText: l10n.projectBudget),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ).tagged('project_form.budget'),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _tags,
                  style: fieldStyle,
                  decoration: dashFieldDecoration(t, labelText: l10n.projectTags),
                ).tagged('project_form.tags'),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _url,
                  style: fieldStyle,
                  decoration: dashFieldDecoration(t, labelText: l10n.projectUrl),
                  keyboardType: TextInputType.url,
                ).tagged('project_form.url'),
                const SizedBox(height: 12),
                _parentDropdown(l10n, t, fieldStyle),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notes,
                  style: fieldStyle,
                  decoration: dashFieldDecoration(t, labelText: l10n.projectNotes),
                  maxLines: 4,
                ).tagged('project_form.notes'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _colorRow(AppLocalizations l10n, DashTokens t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            l10n.projectColor,
            style: t.label.copyWith(color: t.textSecondary),
          ),
        ),
        const SizedBox(height: 8),
        ProjectColorSelector(
          selected: _color,
          onChanged: (hex) => setState(() => _color = hex),
        ),
      ],
    );
  }

  Widget _dueDateRow(AppLocalizations l10n, DashTokens t) {
    final label = _dueDate == null
        ? l10n.projectDueDate
        : '${l10n.projectDueDate}: ${DateTimeFormats.of(context).date(_dueDate!)}';
    return Row(
      children: [
        Icon(Icons.event_outlined, color: t.textSecondary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: t.body,
          ),
        ),
        if (_dueDate != null)
          IconButton(
            icon: Icon(Icons.clear, color: t.textSecondary),
            tooltip: l10n.projectDueDateClear,
            onPressed: () => setState(() => _dueDate = null),
          ).tagged('project_form.clear_due_date'),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: t.textPrimary,
            side: BorderSide(color: t.cardBorder),
          ),
          onPressed: _pickDueDate,
          child: Text(l10n.projectDueDate),
        ).tagged('project_form.due_date'),
      ],
    );
  }

  Widget _parentDropdown(AppLocalizations l10n, DashTokens t, TextStyle fieldStyle) {
    final projects = ref.watch(projectsListProvider).valueOrNull ?? const [];
    // Cannot parent a project to itself.
    final options =
        projects.where((p) => p.id != widget.existing?.id).toList();
    final parentId = _parentId;
    // `projects` is status-filtered (and may still be loading) — the current
    // parent can be absent from `options` (e.g. it's archived/completed while
    // the active filter is "active"). Inject a synthetic entry so the
    // dropdown's value always matches one of `items`, else DropdownButton
    // asserts "exactly zero or one item with [value]" and the sheet crashes.
    final missingParent =
        parentId != null && !options.any((p) => p.id == parentId);
    return DropdownButtonFormField<int?>(
      initialValue: _parentId,
      style: fieldStyle,
      dropdownColor: t.isDark ? const Color(0xFF141A13) : Colors.white,
      decoration: dashFieldDecoration(t, labelText: l10n.projectParent),
      items: [
        DropdownMenuItem(
          value: null,
          child:
              logTag('project_form.parent_none', Text(l10n.projectParentNone)),
        ),
        if (missingParent)
          DropdownMenuItem(
            value: parentId,
            // One id for every project row: the name is the user's own text.
            child: logTag(
              'project_form.parent_option',
              Text(
                widget.existing?.parentName ?? '#$parentId',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        for (final p in options)
          DropdownMenuItem(
            value: p.id,
            child: logTag('project_form.parent_option', Text(p.name)),
          ),
      ],
      onChanged: (v) => setState(() => _parentId = v),
    ).tagged('project_form.parent');
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);

    final dueIso =
        _dueDate == null ? null : calendarDateToJson(_dueDate!);

    ActionOutcome result;
    try {
      if (widget.isEdit) {
        result = await ref
            .read(projectDetailProvider(widget.existing!.id).notifier)
            .save(ProjectUpdate(
              name: _name.text.trim(),
              description: _emptyToNull(_description.text),
              color: _color,
              status: _status,
              targetCount: _intOrNull(_targetCount.text),
              targetPartsCount: _intOrNull(_targetParts.text),
              targetSets: _intOrNull(_targetSets.text),
              notes: _emptyToNull(_notes.text),
              tags: _emptyToNull(_tags.text),
              dueDate: dueIso,
              priority: _priority,
              budget: _doubleOrNull(_budget.text),
              parentId: _parentId,
              url: _emptyToNull(_url.text),
            ));
      } else {
        await ref.read(projectsRepositoryProvider).create(ProjectCreate(
              name: _name.text.trim(),
              description: _emptyToNull(_description.text),
              color: _color,
              targetCount: _intOrNull(_targetCount.text),
              targetPartsCount: _intOrNull(_targetParts.text),
              targetSets: _intOrNull(_targetSets.text),
              notes: _emptyToNull(_notes.text),
              tags: _emptyToNull(_tags.text),
              dueDate: dueIso,
              priority: _priority,
              budget: _doubleOrNull(_budget.text),
              parentId: _parentId,
              url: _emptyToNull(_url.text),
            ));
        result = ActionOutcome.ok;
      }
    } on Object {
      result = ActionOutcome.failed(
        const ApiException(AppErrorCode.malformedResponse),
        action: 'project_form.save',
      );
    }

    await ref.read(projectsListProvider.notifier).refresh();
    if (!mounted) return;
    setState(() => _saving = false);

    messenger.snack(result.messageFor(l10n) ?? l10n.projectSaved);
    if (result.isOk) navigator.pop();
  }

  String? _emptyToNull(String s) => s.trim().isEmpty ? null : s.trim();
  int? _intOrNull(String s) => int.tryParse(s.trim());
  double? _doubleOrNull(String s) => double.tryParse(s.trim().replaceAll(',', '.'));
}

/// Imperative entry: open the create form.
Future<void> openProjectCreate(BuildContext context) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ProjectFormScreen()),
    );

/// Imperative entry: open the edit form for [project].
Future<void> openProjectEdit(BuildContext context, ProjectResponse project) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
          builder: (_) => ProjectFormScreen(existing: project)),
    );
