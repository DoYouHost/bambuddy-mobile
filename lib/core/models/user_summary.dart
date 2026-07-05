import 'json_utils.dart';

/// Minimal user record from `GET /users/` — id + display name only, used by
/// the Stats "filter by user" picker. The endpoint is permission-gated
/// server-side (`stats:filter_by_user` or admin); a 403 there just means
/// this identity can't filter by user, not an error.
class UserSummary {
  const UserSummary({required this.id, required this.username});

  factory UserSummary.fromJson(Map<String, dynamic> json) => UserSummary(
        id: toInt(json['id']),
        username: toStringOrNull(json['username']) ?? '?',
      );

  final int id;
  final String username;
}
