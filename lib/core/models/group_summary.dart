import 'json_utils.dart';

/// A group as `GET /groups/` sends it (`GroupResponse`,
/// `backend/app/schemas/group.py:33`). Used here for the membership picker in
/// the account form; the group screens of their own come later.
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
