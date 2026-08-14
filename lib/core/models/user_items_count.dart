import 'json_utils.dart';

/// What an account owns — `GET /users/{id}/items-count`
/// (`backend/app/api/routes/users.py::update_user`). Deleting the account asks
/// what happens to exactly these three, so the list shows them before anyone
/// gets that far.
class UserItemsCount {
  const UserItemsCount({
    required this.archives,
    required this.queueItems,
    required this.libraryFiles,
  });

  factory UserItemsCount.fromJson(Map<String, dynamic> json) => UserItemsCount(
        archives: toInt(json['archives']),
        queueItems: toInt(json['queue_items']),
        libraryFiles: toInt(json['library_files']),
      );

  final int archives;
  final int queueItems;
  final int libraryFiles;

  int get total => archives + queueItems + libraryFiles;
}
