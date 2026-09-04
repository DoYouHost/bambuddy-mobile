import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diagnostics/log_tag.dart';
import '../../core/format/datetime_format.dart';
import '../../core/models/api_key.dart';
import '../../core/theme/dash_text.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common/dash_snack.dart';
import '../common/system_insets.dart';
import 'api_key_labels.dart';
import 'api_keys_providers.dart';
import 'api_keys_screen.dart';
import 'user_messages.dart';
import 'users_providers.dart';

/// Issue a new key, or change what an existing one may do.
///
/// Creating ends in [showCreatedKeyDialog]: the server answers with the key
/// once and keeps only its hash, so that dialog is the last place it exists.
class ApiKeyFormScreen extends ConsumerStatefulWidget {
  const ApiKeyFormScreen({super.key, this.existing});

  final ApiKey? existing;

  bool get isEdit => existing != null;

  @override
  ConsumerState<ApiKeyFormScreen> createState() => _ApiKeyFormScreenState();
}

class _ApiKeyFormScreenState extends ConsumerState<ApiKeyFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;

  late Set<ApiKeyScope> _scopes;
  late bool _enabled;
  late Set<int>? _printerIds;
  DateTime? _expiresAt;
  bool _saving = false;

  /// What a fresh key starts with: read-only. Every other scope is a decision
  /// someone has to make — the server's own defaults hand out queue, library,
  /// inventory, maintenance, archives and projects unless told otherwise.
  static const _defaultScopes = {ApiKeyScope.readStatus};

  @override
  void initState() {
    super.initState();
    final k = widget.existing;
    _name = TextEditingController(text: k?.name ?? '');
    _scopes = {...?k?.scopes, if (k == null) ..._defaultScopes};
    _enabled = k?.enabled ?? true;
    _printerIds = k?.printerIds == null ? null : {...k!.printerIds!};
    _expiresAt = k?.expiresAt;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final printers = ref.watch(apiKeyPrinterOptionsProvider).valueOrNull ?? const [];
    final fmt = DateTimeFormats.of(context);

    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: dashAppBar(
          context,
          title: widget.isEdit ? l10n.apiKeysEditTitle : l10n.apiKeysCreateTitle,
          actions: [
            TextButton(
              style: TextButton.styleFrom(foregroundColor: t.accentGreenInk),
              onPressed: _saving ? null : _submit,
              child: Text(l10n.usersSave),
            ).tagged('api_key_form.save'),
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
                  style: t.bodyStrong,
                  decoration: dashFieldDecoration(
                    t,
                    labelText: l10n.apiKeysFieldName,
                    helperText: l10n.apiKeysFieldNameHint,
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? l10n.usersFieldRequired
                      : null,
                ).tagged('api_key_form.name'),
                if (widget.isEdit) ...[
                  const SizedBox(height: 8),
                  SwitchListTile(
                    value: _enabled,
                    onChanged: (v) => setState(() => _enabled = v),
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.apiKeysFieldEnabled),
                    subtitle: Text(l10n.apiKeysFieldEnabledHint),
                  ).tagged('api_key_form.enabled'),
                ],
                const SizedBox(height: 16),
                _SectionLabel(text: l10n.apiKeysScopesHeader),
                const SizedBox(height: 4),
                Text(
                  l10n.apiKeysScopesHint,
                  style: t.microSoft,
                ),
                for (final scope in ApiKeyScope.values)
                  SwitchListTile(
                    value: _scopes.contains(scope),
                    onChanged: (on) => setState(() {
                      on ? _scopes.add(scope) : _scopes.remove(scope);
                    }),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(apiKeyScopeLabel(l10n, scope)),
                    subtitle: switch (apiKeyScopeHint(l10n, scope)) {
                      final hint? => Text(hint),
                      _ => null,
                    },
                  ).tagged('api_key_form.scope'),
                if (printers.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _SectionLabel(text: l10n.apiKeysPrintersHeader),
                  const SizedBox(height: 4),
                  SwitchListTile(
                    value: _printerIds == null,
                    onChanged: (all) => setState(
                      () => _printerIds = all ? null : <int>{},
                    ),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(l10n.apiKeysAllPrinters),
                    subtitle: Text(l10n.apiKeysAllPrintersHint),
                  ).tagged('api_key_form.all_printers'),
                  if (_printerIds != null)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final p in printers)
                          FilterChip(
                            label: Text(p.name),
                            selected: _printerIds!.contains(p.id),
                            onSelected: (on) => setState(() {
                              on
                                  ? _printerIds!.add(p.id)
                                  : _printerIds!.remove(p.id);
                            }),
                          ).tagged('api_key_form.printer'),
                      ],
                    ),
                ],
                const SizedBox(height: 16),
                _SectionLabel(text: l10n.apiKeysExpiryHeader),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.schedule, color: t.textSecondary),
                  title: Text(
                    _expiresAt == null
                        ? l10n.apiKeysNoExpiry
                        : fmt.dateNamedMonth(_expiresAt!),
                  ),
                  subtitle: Text(l10n.apiKeysExpiryHint),
                  trailing: _expiresAt == null
                      ? null
                      : IconButton(
                          icon: Icon(Icons.clear, color: t.textSecondary),
                          tooltip: l10n.apiKeysExpiryClear,
                          onPressed: () => setState(() => _expiresAt = null),
                        ).tagged('api_key_form.clear_expiry'),
                  onTap: _pickExpiry,
                ).tagged('api_key_form.expiry'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiresAt ?? now.add(const Duration(days: 90)),
      firstDate: now,
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) setState(() => _expiresAt = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final repo = ref.read(apiKeysRepositoryProvider);
    final existing = widget.existing;
    setState(() => _saving = true);

    final name = _name.text.trim();
    final printerIds = _printerIds?.toList()?..sort();
    String? created;

    final result = await runUserWrite(() async {
      if (existing == null) {
        final answer = await repo.create(ApiKeyCreateInput(
          name: name,
          scopes: _scopes,
          printerIds: printerIds,
          expiresAt: _expiresAt,
        ));
        created = answer.key;
        return;
      }
      final body = ApiKeyUpdateInput(
        name: name == existing.name ? null : name,
        scopes: _sameScopes(existing.scopes) ? null : _scopes,
        printerIds: _printerIds == null ? null : printerIds,
        // Null on the wire is the only way to say "all printers again".
        clearPrinterIds: _printerIds == null && existing.printerIds != null,
        enabled: _enabled == existing.enabled ? null : _enabled,
        expiresAt: _expiresAt == existing.expiresAt ? null : _expiresAt,
      );
      if (body.isEmpty) return;
      await repo.update(existing.id, body);
    }, 'api_key_form.save');

    await ref.read(apiKeysListProvider.notifier).refresh();
    if (!mounted) return;
    setState(() => _saving = false);

    if (!result.ok) {
      messenger.snack(userWriteMessage(l10n, result));
      return;
    }
    // Leave the form first: the key dialog is the last chance to read the key,
    // and it should not be sitting on top of a screen that can be popped by a
    // back gesture into nothing.
    navigator.pop();
    final key = created;
    if (key != null && key.isNotEmpty) {
      await showCreatedKeyDialog(navigator.context, key);
    } else {
      messenger.snack(l10n.apiKeysSaved);
    }
  }

  bool _sameScopes(Set<ApiKeyScope> current) =>
      current.length == _scopes.length && current.containsAll(_scopes);
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Text(
      text,
      style: t.bodyBold.copyWith(letterSpacing: 0.3),
    );
  }
}

/// Imperative entry: issue a key.
Future<void> openApiKeyCreate(BuildContext context) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ApiKeyFormScreen()),
    );

/// Imperative entry: edit [apiKey].
Future<void> openApiKeyEdit(BuildContext context, ApiKey apiKey) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
          builder: (_) => ApiKeyFormScreen(existing: apiKey)),
    );
