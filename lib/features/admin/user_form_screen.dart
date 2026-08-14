import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diagnostics/log_tag.dart';
import '../../core/models/current_user.dart';
import '../../core/models/group_summary.dart';
import '../../core/models/user_write.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import 'user_messages.dart';
import 'users_providers.dart';

/// Create / edit an account. [existing] null creates (POST), otherwise the
/// form prefills and sends only what changed (PATCH acts on "not null", so
/// sending everything would rewrite fields nobody touched).
///
/// The rules — last admin, name taken, LDAP password — stay server-side. The
/// form's own validation is limited to what it can answer without asking:
/// a required field left blank, and the password complexity the server would
/// otherwise reject with a 422.
class UserFormScreen extends ConsumerStatefulWidget {
  const UserFormScreen({super.key, this.existing});

  final CurrentUser? existing;

  bool get isEdit => existing != null;

  @override
  ConsumerState<UserFormScreen> createState() => _UserFormScreenState();
}

class _UserFormScreenState extends ConsumerState<UserFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _username;
  late final TextEditingController _email;
  late final TextEditingController _password;
  late final TextEditingController _confirmPassword;

  late bool _isActive;
  late Set<int> _groupIds;
  bool _saving = false;

  /// LDAP accounts live in the directory: the server refuses a password for
  /// them (`users.py::update_user`), so the field is not offered.
  bool get _isLdap => widget.existing?.authSource == 'ldap';

  @override
  void initState() {
    super.initState();
    final u = widget.existing;
    _username = TextEditingController(text: u?.username ?? '');
    _email = TextEditingController(text: u?.email ?? '');
    _password = TextEditingController();
    _confirmPassword = TextEditingController();
    _isActive = u?.isActive ?? true;
    _groupIds = {for (final g in u?.groups ?? const <UserGroup>[]) g.id};
  }

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final advanced =
        ref.watch(advancedAuthStatusProvider).valueOrNull ?? AdvancedAuthStatus.legacy;
    final groups = ref.watch(groupOptionsProvider).valueOrNull ?? const [];
    final fieldStyle = TextStyle(
      fontFamily: DashTokens.fontUi,
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: t.textPrimary,
    );
    // With advanced authentication on, the server picks the password itself and
    // mails it — an admin neither sets nor sees one (`users.py::create_user`).
    final serverPicksPassword = advanced.enabled && !widget.isEdit;

    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: dashAppBar(
          context,
          title: widget.isEdit ? l10n.usersEditTitle : l10n.usersCreateTitle,
          actions: [
            TextButton(
              style: TextButton.styleFrom(foregroundColor: t.accentGreenInk),
              onPressed: _saving ? null : _submit,
              child: Text(l10n.usersSave),
            ).tagged('user_form.save'),
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
                  controller: _username,
                  style: fieldStyle,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration:
                      dashFieldDecoration(t, labelText: l10n.usersFieldUsername),
                  textInputAction: TextInputAction.next,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? l10n.usersFieldRequired
                      : null,
                ).tagged('user_form.username'),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _email,
                  style: fieldStyle,
                  autocorrect: false,
                  keyboardType: TextInputType.emailAddress,
                  decoration: dashFieldDecoration(
                    t,
                    labelText: advanced.enabled
                        ? l10n.usersFieldEmailRequired
                        : l10n.usersFieldEmail,
                    helperText:
                        advanced.enabled ? l10n.usersEmailAdvancedHint : null,
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (v) =>
                      advanced.enabled && (v == null || v.trim().isEmpty)
                          ? l10n.usersFieldRequired
                          : null,
                ).tagged('user_form.email'),
                if (serverPicksPassword) ...[
                  const SizedBox(height: 12),
                  _Notice(
                    icon: Icons.mark_email_read_outlined,
                    text: l10n.usersPasswordMailed,
                    accent: t.accentBlue,
                  ),
                  if (!advanced.smtpConfigured) ...[
                    const SizedBox(height: 8),
                    // Creation succeeds and the mail silently doesn't go out
                    // (`users.py::create_user` logs it and returns 201),
                    // leaving an account nobody can sign in to.
                    _Notice(
                      icon: Icons.warning_amber_rounded,
                      text: l10n.usersNoSmtpWarning,
                      accent: t.accentOrange,
                    ),
                  ],
                ] else if (_isLdap) ...[
                  const SizedBox(height: 12),
                  _Notice(
                    icon: Icons.dns_outlined,
                    text: l10n.usersLdapPasswordNote,
                    accent: t.accentBlue,
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _password,
                    style: fieldStyle,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: dashFieldDecoration(
                      t,
                      labelText: widget.isEdit
                          ? l10n.usersFieldNewPassword
                          : l10n.usersFieldPassword,
                      helperText: widget.isEdit
                          ? l10n.usersPasswordKeepHint
                          : l10n.usersPasswordRulesHint,
                    ),
                    validator: _validatePassword,
                    onChanged: (_) => setState(() {}),
                  ).tagged('user_form.password'),
                  // A password nobody can read back is a password nobody can
                  // recover from a typo — the web form asks twice for the same
                  // reason. On edit the field only appears once there is
                  // something to confirm.
                  if (!widget.isEdit || _password.text.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _confirmPassword,
                      style: fieldStyle,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: dashFieldDecoration(
                        t,
                        labelText: l10n.usersFieldConfirmPassword,
                      ),
                      validator: _validateConfirmPassword,
                    ).tagged('user_form.confirm_password'),
                  ],
                ],
                if (widget.isEdit) ...[
                  const SizedBox(height: 8),
                  SwitchListTile(
                    value: _isActive,
                    onChanged: (v) => setState(() => _isActive = v),
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.usersFieldActive),
                    subtitle: Text(l10n.usersActiveHint),
                  ).tagged('user_form.active'),
                ],
                if (groups.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _GroupPicker(
                    groups: groups,
                    selected: _groupIds,
                    onToggle: (id, on) => setState(
                      () => on ? _groupIds.add(id) : _groupIds.remove(id),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _validatePassword(String? value) {
    final l10n = AppLocalizations.of(context);
    final text = value ?? '';
    // On edit an empty field means "leave the password alone" — the PATCH
    // simply omits it.
    if (text.isEmpty) {
      return widget.isEdit ? null : l10n.usersFieldRequired;
    }
    return passwordRuleMessage(l10n, text);
  }

  String? _validateConfirmPassword(String? value) {
    final l10n = AppLocalizations.of(context);
    if (_password.text.isEmpty) return null;
    return (value ?? '') == _password.text
        ? null
        : l10n.usersPasswordsDoNotMatch;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final repo = ref.read(usersRepositoryProvider);
    final existing = widget.existing;
    setState(() => _saving = true);

    final username = _username.text.trim();
    final email = _email.text.trim();
    final password = _password.text;
    final groupIds = _groupIds.toList()..sort();

    final result = await runUserWrite(() async {
      if (existing == null) {
        await repo.create(UserCreateInput(
          username: username,
          // With advanced authentication on the server generates it; sending
          // one anyway would be ignored, so nothing is sent.
          password: password.isEmpty ? null : password,
          email: email.isEmpty ? null : email,
          // The role is deliberately left at its default and never offered as a
          // field: admin is granted by putting the account in the
          // Administrators group, which is the one path bambuddy's own UI
          // shows. `is_admin` is computed from either
          // (`backend/app/models/user.py::get_permissions`), so the group is
          // enough.
          groupIds: groupIds,
        ));
        return;
      }
      final body = UserUpdateInput(
        username: username == existing.username ? null : username,
        password: password.isEmpty ? null : password,
        // An empty field on an account that had an e-mail is a deliberate
        // clearing, and the server takes "" for that — null would mean
        // "unchanged" (`users.py::update_user`).
        email: email == (existing.email ?? '') ? null : email,
        isActive: _isActive == existing.isActive ? null : _isActive,
        groupIds: _sameGroups(existing.groups, groupIds) ? null : groupIds,
      );
      if (body.isEmpty) return;
      await repo.update(existing.id, body);
    }, 'user_form.save');

    await ref.read(usersListProvider.notifier).refresh();
    // Editing your own account can change your own role, groups and therefore
    // what the app offers you — re-read the identity rather than keep the one
    // from before the edit.
    if (result.ok && existing != null) {
      final self = ref.read(currentUserProvider).valueOrNull;
      if (self != null && self.id == existing.id) {
        await ref.read(currentUserProvider.notifier).refresh();
      }
    }
    if (!mounted) return;
    setState(() => _saving = false);

    messenger.showSnackBar(SnackBar(
      content: Text(
        result.ok ? l10n.usersSaved : userWriteMessage(l10n, result),
      ),
    ));
    if (result.ok) navigator.pop();
  }

  static bool _sameGroups(List<UserGroup> current, List<int> picked) {
    final ids = [for (final g in current) g.id]..sort();
    if (ids.length != picked.length) return false;
    for (var i = 0; i < ids.length; i++) {
      if (ids[i] != picked[i]) return false;
    }
    return true;
  }
}

/// Multi-select over the server's groups — and the only way to make an account
/// an admin: `Administrators` is a group like any other here. Membership is
/// also editable from the group side later on; this is the "editing a person"
/// path.
class _GroupPicker extends StatelessWidget {
  const _GroupPicker({
    required this.groups,
    required this.selected,
    required this.onToggle,
  });

  final List<GroupSummary> groups;
  final Set<int> selected;
  final void Function(int id, bool selected) onToggle;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.usersFieldGroups,
          style: TextStyle(
            fontFamily: DashTokens.fontUi,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: t.textSecondary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          l10n.usersGroupsAdminHint,
          style: TextStyle(
            fontFamily: DashTokens.fontUi,
            fontSize: 11.5,
            color: t.textTertiary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final g in groups)
              FilterChip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(g.name),
                    // The groups that ship with the server, marked as bambuddy
                    // marks them — they cannot be renamed or repurposed, so
                    // what they grant is the same on every install.
                    if (g.isSystem) ...[
                      const SizedBox(width: 6),
                      Text(
                        l10n.usersGroupSystem,
                        style: TextStyle(
                          fontFamily: DashTokens.fontUi,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: t.accentOrange,
                        ),
                      ),
                    ],
                  ],
                ),
                selected: selected.contains(g.id),
                onSelected: (on) => onToggle(g.id, on),
              ).tagged('user_form.group'),
          ],
        ),
      ],
    );
  }
}

/// Tinted note above a field — says what the server will do, in the place
/// where the missing input would otherwise be.
class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.text,
    required this.accent,
  });

  final IconData icon;
  final String text;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontFamily: DashTokens.fontUi,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: t.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Imperative entry: create a new account.
Future<void> openUserCreate(BuildContext context) => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const UserFormScreen()),
    );

/// Imperative entry: edit [user].
Future<void> openUserEdit(BuildContext context, CurrentUser user) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => UserFormScreen(existing: user)),
    );
