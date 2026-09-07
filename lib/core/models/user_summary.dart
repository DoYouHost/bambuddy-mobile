import 'json_utils.dart';

/// Minimal user record — id + display name only, used by the Stats "filter by
/// user" picker.
///
/// Parses both listings the picker can be answered by: `GET /users/slim`,
/// whose whole shape this is (`UserSlim`, 1.2.6+), and the full `GET /users/`
/// (`UserResponse`), which carries the same two fields among many others. That
/// is what lets [StatsRepository.fetchUsers] fall back between them without
/// the picker knowing which one answered.
///
/// Both are permission-gated server-side; a 403 from both just means this
/// identity can't filter by user, not an error.
class UserSummary {
  const UserSummary({required this.id, required this.username});

  factory UserSummary.fromJson(Map<String, dynamic> json) => UserSummary(
    id: toInt(json['id']),
    username: toStringOrNull(json['username']) ?? '?',
  );

  final int id;
  final String username;
}
