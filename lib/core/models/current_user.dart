import 'json_utils.dart';

/// One group the signed-in user belongs to (`GroupBrief` server-side:
/// `backend/app/schemas/auth.py::GroupBrief` — only `id` and `name` are sent,
/// the group's own permission list is not).
class UserGroup {
  const UserGroup({required this.id, required this.name});

  factory UserGroup.fromJson(Map<String, dynamic> json) => UserGroup(
        id: toInt(json['id']),
        name: toStringOrNull(json['name']) ?? '',
      );

  final int id;
  final String name;
}

/// The signed-in identity, as `UserResponse`
/// (`backend/app/schemas/auth.py::UserResponse`). Comes from two places that
/// send the identical shape: the `user` object inside `POST /auth/login`'s
/// answer, and `GET /auth/me` when a session is restored.
class CurrentUser {
  const CurrentUser({
    required this.id,
    required this.username,
    required this.isAdmin,
    this.email,
    this.role = 'user',
    this.isActive = true,
    this.authSource = 'local',
    this.groups = const [],
    this.permissions = const {},
    this.permissionsKnown = true,
    this.createdAt,
  });

  factory CurrentUser.fromJson(Map<String, dynamic> json) => CurrentUser(
        id: toInt(json['id']),
        username: toStringOrNull(json['username']) ?? '',
        email: toStringOrNull(json['email']),
        role: toStringOrNull(json['role']) ?? 'user',
        isActive: json['is_active'] != false,
        isAdmin: json['is_admin'] == true,
        authSource: toStringOrNull(json['auth_source']) ?? 'local',
        groups: parseJsonList(json['groups'], UserGroup.fromJson),
        permissions: toStringList(json['permissions']).toSet(),
        // Key presence, not "has entries": the server declares `permissions:
        // list[str] = []` and computes it as the union over the user's groups
        // (`backend/app/models/user.py::get_permissions`), so an empty list is
        // a real answer — a member of a group that grants nothing. Treating
        // that as "unknown" would show them every screen and let the server
        // answer 403. Only a response that omits the field entirely (or sends
        // something that isn't a list) leaves us without an answer.
        permissionsKnown: json['permissions'] is List,
        createdAt: dateTimeFromJson(json['created_at']),
      );

  final int id;
  final String username;
  final String? email;

  /// Kept for backward compatibility server-side and here — [isAdmin] is the
  /// computed truth (role *or* group membership), `role` is the legacy label.
  final String role;

  final bool isActive;

  /// Admins bypass every permission check server-side
  /// (`backend/app/models/user.py::has_permission`), which is why [can]
  /// short-circuits on it rather than looking for the permission in
  /// [permissions].
  final bool isAdmin;

  /// `local` or `ldap`.
  final String authSource;

  final List<UserGroup> groups;

  /// The union of the permissions granted by the user's groups. Meaningful
  /// only when [permissionsKnown]; empty and unknown are different answers.
  final Set<String> permissions;

  /// Whether the server actually told us the permission set. False for a
  /// response without the field — an older server, or a shape we don't
  /// recognise — and then [can] answers yes to everything, leaving the server
  /// as the sole enforcer exactly as it is today.
  final bool permissionsKnown;

  final DateTime? createdAt;

  /// Whether this user may do [permission] — mirroring `User.has_permission`
  /// (`backend/app/models/user.py::has_permission`): admin passes everything,
  /// otherwise the permission has to be in the set. The server matches the
  /// string exactly, with no wildcard form, so neither do we.
  ///
  /// Careful with a session authenticated by an API key — what [permissions]
  /// holds there depends on the server generation. A server up to 1.2.5.x
  /// describes a key as an admin holding every permission, so this says yes to
  /// everything; 1.2.6+ reports what the key can genuinely exercise
  /// (`backend/app/api/routes/auth.py::_api_key_to_user_response`). Neither is
  /// a substitute for the gate: the routes refuse a key every administrative
  /// permission outright, whatever it was told. Anything gating on
  /// users/groups/api-keys must go through `identifiedPermissionProvider`,
  /// which accounts for that.
  bool can(String permission) =>
      isAdmin || !permissionsKnown || permissions.contains(permission);
}

/// The permission strings this app gates on. The full list lives in
/// `backend/app/core/permissions.py` (`class Permission`); only the ones a
/// screen here needs are mirrored, so the two don't have to be kept in step
/// wholesale.
abstract final class Permissions {
  /// `backend/app/core/permissions.py::Permission`
  static const usersRead = 'users:read';

  /// `backend/app/core/permissions.py::Permission`
  static const groupsRead = 'groups:read';

  /// `backend/app/core/permissions.py::Permission`
  static const apiKeysRead = 'api_keys:read';

  /// Managing keys needs no admin role on top, unlike users and groups — these
  /// permissions are the whole gate (`routes/api_keys.py::create_api_key`).
  static const apiKeysCreate = 'api_keys:create';
  static const apiKeysUpdate = 'api_keys:update';
  static const apiKeysDelete = 'api_keys:delete';
}
