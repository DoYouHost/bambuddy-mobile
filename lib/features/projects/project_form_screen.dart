import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/project.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
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
      _budget,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEdit ? l10n.projectEdit : l10n.projectCreate),
        actions: [
          TextButton(
            onPressed: _saving ? null : _submit,
            child: Text(l10n.projectSave),
          ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: _saving,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              TextFormField(
                controller: _name,
                decoration: InputDecoration(labelText: l10n.projectName),
                textInputAction: TextInputAction.next,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? l10n.projectNameRequired : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _description,
                decoration: InputDecoration(labelText: l10n.projectDescription),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _status,
                      decoration: InputDecoration(labelText: l10n.projectStatus),
                      items: [
                        for (final s in projectStatusValues)
                          DropdownMenuItem(
                              value: s, child: Text(projectStatusLabel(l10n, s))),
                      ],
                      onChanged: (v) => setState(() => _status = v ?? _status),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _priority,
                      decoration: InputDecoration(labelText: l10n.projectPriority),
                      items: [
                        for (final s in projectPriorityValues)
                          DropdownMenuItem(
                              value: s, child: Text(projectPriorityLabel(l10n, s))),
                      ],
                      onChanged: (v) => setState(() => _priority = v ?? _priority),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _colorRow(l10n),
              const SizedBox(height: 12),
              _dueDateRow(l10n),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _targetCount,
                      decoration:
                          InputDecoration(labelText: l10n.projectTargetCount),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _targetParts,
                      decoration: InputDecoration(
                          labelText: l10n.projectTargetPartsCount),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _budget,
                decoration: InputDecoration(labelText: l10n.projectBudget),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _tags,
                decoration: InputDecoration(labelText: l10n.projectTags),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _url,
                decoration: InputDecoration(labelText: l10n.projectUrl),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 12),
              _parentDropdown(l10n),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                decoration: InputDecoration(labelText: l10n.projectNotes),
                maxLines: 4,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _colorRow(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(l10n.projectColor,
              style: Theme.of(context).textTheme.bodySmall),
        ),
        const SizedBox(height: 8),
        ProjectColorSelector(
          selected: _color,
          onChanged: (hex) => setState(() => _color = hex),
        ),
      ],
    );
  }

  Widget _dueDateRow(AppLocalizations l10n) {
    final label = _dueDate == null
        ? l10n.projectDueDate
        : '${l10n.projectDueDate}: ${_fmtDate(_dueDate!)}';
    return Row(
      children: [
        const Icon(Icons.event_outlined),
        const SizedBox(width: 12),
        Expanded(child: Text(label)),
        if (_dueDate != null)
          IconButton(
            icon: const Icon(Icons.clear),
            tooltip: l10n.projectDueDateClear,
            onPressed: () => setState(() => _dueDate = null),
          ),
        OutlinedButton(
          onPressed: _pickDueDate,
          child: Text(l10n.projectDueDate),
        ),
      ],
    );
  }

  Widget _parentDropdown(AppLocalizations l10n) {
    final projects = ref.watch(projectsListProvider).valueOrNull ?? const [];
    // Cannot parent a project to itself.
    final options =
        projects.where((p) => p.id != widget.existing?.id).toList();
    return DropdownButtonFormField<int?>(
      initialValue: _parentId,
      decoration: InputDecoration(labelText: l10n.projectParent),
      items: [
        DropdownMenuItem(value: null, child: Text(l10n.projectParentNone)),
        for (final p in options)
          DropdownMenuItem(value: p.id, child: Text(p.name)),
      ],
      onChanged: (v) => setState(() => _parentId = v),
    );
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

    final dueIso = _dueDate == null
        ? null
        : '${_dueDate!.year.toString().padLeft(4, '0')}-'
            '${_dueDate!.month.toString().padLeft(2, '0')}-'
            '${_dueDate!.day.toString().padLeft(2, '0')}';

    ProjectActionResult result;
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
              notes: _emptyToNull(_notes.text),
              tags: _emptyToNull(_tags.text),
              dueDate: dueIso,
              priority: _priority,
              budget: _doubleOrNull(_budget.text),
              parentId: _parentId,
              url: _emptyToNull(_url.text),
            ));
        result = ProjectActionResult.ok;
      }
    } on Object {
      result = ProjectActionResult.error;
    }

    await ref.read(projectsListProvider.notifier).refresh();
    if (!mounted) return;
    setState(() => _saving = false);

    messenger.showSnackBar(SnackBar(
      content: Text(switch (result) {
        ProjectActionResult.ok => l10n.projectSaved,
        ProjectActionResult.forbidden => l10n.projectActionForbidden,
        ProjectActionResult.error => l10n.projectActionFailed,
      }),
    ));
    if (result == ProjectActionResult.ok) navigator.pop();
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

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
