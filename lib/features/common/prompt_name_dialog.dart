import 'package:flutter/material.dart';

import '../../core/diagnostics/log_tag.dart';
import '../../l10n/app_localizations.dart';

/// Shared single-line text prompt (new folder, rename, new tag…). Sibling of
/// [confirmDialog]: same reason to exist — the same dialog was being rebuilt per
/// screen, and each copy had to remember to dispose its controller.
///
/// Returns the trimmed text, or `null` when cancelled/dismissed. An empty
/// result is returned as `null` too, so callers don't each re-check it.
///
/// [id] names the field and both buttons in the diagnostic log
/// (`<id>.field` / `<id>.save` / `<id>.cancel`). The default keeps the wire
/// values the file manager's prompt already logs.
Future<String?> promptName(
  BuildContext context, {
  required String title,
  required String label,
  String? initial,
  String? confirmLabel,
  String id = 'name_prompt',
}) async {
  final name = await showDialog<String>(
    context: context,
    builder: (_) => _PromptNameDialog(
      title: title,
      label: label,
      initial: initial,
      confirmLabel: confirmLabel,
      id: id,
    ),
  );
  final trimmed = name?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

/// A StatefulWidget so it owns and disposes its own controller in the State
/// lifecycle (disposing a function-local controller right after `await
/// showDialog` races the dialog's exit animation).
class _PromptNameDialog extends StatefulWidget {
  const _PromptNameDialog({
    required this.title,
    required this.label,
    required this.id,
    this.initial,
    this.confirmLabel,
  });

  final String title;
  final String label;
  final String id;
  final String? initial;
  final String? confirmLabel;

  @override
  State<_PromptNameDialog> createState() => _PromptNameDialogState();
}

class _PromptNameDialogState extends State<_PromptNameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(labelText: widget.label),
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ).tagged('${widget.id}.field'),
      actions: [
        logTag(
          '${widget.id}.cancel',
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
        ),
        logTag(
          '${widget.id}.save',
          FilledButton(
            onPressed: () => Navigator.pop(context, _controller.text.trim()),
            child: Text(widget.confirmLabel ?? l10n.fmSave),
          ),
        ),
      ],
    );
  }
}
