import 'json_utils.dart';

/// A group as `GET /groups/` sends it
/// (`backend/app/schemas/group.py::GroupResponse`) — the list and the
/// membership picker in the account form.
class GroupSummary {
  const GroupSummary({
    required this.id,
    required this.name,
    this.description,
    this.permissions = const [],
    this.isSystem = false,
    this.userCount = 0,
  });

  factory GroupSummary.fromJson(Map<String, dynamic> json) => GroupSummary(
        id: toInt(json['id']),
        name: toStringOrNull(json['name']) ?? '',
        description: toStringOrNull(json['description']),
        permissions: toStringList(json['permissions']),
        // `Administrators` and friends: the server refuses to rename them or
        // to change what they grant.
        isSystem: json['is_system'] == true,
        userCount: toInt(json['user_count']),
      );

  final int id;
  final String name;
  final String? description;
  final List<String> permissions;
  final bool isSystem;
  final int userCount;
}

/// One member of a group (`UserBrief`,
/// `backend/app/schemas/group.py::GroupDetailResponse`) — id, name and whether
/// the account is switched on. Not a whole `UserResponse`: the group detail
/// says who is in it, not what each of them may do elsewhere.
class GroupMember {
  const GroupMember({
    required this.id,
    required this.username,
    this.isActive = true,
  });

  factory GroupMember.fromJson(Map<String, dynamic> json) => GroupMember(
        id: toInt(json['id']),
        username: toStringOrNull(json['username']) ?? '',
        isActive: json['is_active'] != false,
      );

  final int id;
  final String username;
  final bool isActive;
}

/// `GET /groups/{id}` — the group plus its member list
/// (`backend/app/schemas/group.py::GroupDetailResponse`).
class GroupDetail extends GroupSummary {
  const GroupDetail({
    required super.id,
    required super.name,
    super.description,
    super.permissions,
    super.isSystem,
    super.userCount,
    this.members = const [],
  });

  factory GroupDetail.fromJson(Map<String, dynamic> json) {
    final summary = GroupSummary.fromJson(json);
    return GroupDetail(
      id: summary.id,
      name: summary.name,
      description: summary.description,
      permissions: summary.permissions,
      isSystem: summary.isSystem,
      userCount: summary.userCount,
      members: parseJsonList(json['users'], GroupMember.fromJson),
    );
  }

  final List<GroupMember> members;
}
