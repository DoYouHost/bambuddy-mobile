import 'json_utils.dart';

/// One permission the server knows, with the label it wants shown
/// (`backend/app/schemas/group.py::PermissionInfo`).
class PermissionInfo {
  const PermissionInfo({required this.value, required this.label});

  factory PermissionInfo.fromJson(Map<String, dynamic> json) {
    final value = toStringOrNull(json['value']) ?? '';
    return PermissionInfo(
      value: value,
      // A server that sends no label leaves the raw string, which is still
      // readable ("queue:create") and better than a blank row.
      label: toStringOrNull(json['label']) ?? value,
    );
  }

  final String value;
  final String label;
}

/// A named group of permissions, as the server groups them
/// (`PERMISSION_CATEGORIES`, `backend/app/core/permissions.py::Permission`).
class PermissionCategory {
  const PermissionCategory({required this.name, required this.permissions});

  factory PermissionCategory.fromJson(Map<String, dynamic> json) =>
      PermissionCategory(
        name: toStringOrNull(json['name']) ?? '',
        permissions: parseJsonList(json['permissions'], PermissionInfo.fromJson),
      );

  final String name;
  final List<PermissionInfo> permissions;
}

/// `GET /groups/permissions` — every permission the server has, by category.
///
/// Fetched rather than mirrored in Dart: the catalog is already past sixty
/// entries and grows with the server, and a stale copy here would quietly
/// hide permissions an admin is trying to grant.
class PermissionCatalog {
  const PermissionCatalog({this.categories = const [], this.all = const []});

  factory PermissionCatalog.fromJson(Map<String, dynamic> json) =>
      PermissionCatalog(
        categories:
            parseJsonList(json['categories'], PermissionCategory.fromJson),
        all: toStringList(json['all_permissions']),
      );

  final List<PermissionCategory> categories;

  /// Every permission string, in the server's order — what "select all" means.
  final List<String> all;

  /// The categories this app has screens for. Everything else is server
  /// administration (users, API keys, settings, backups, …) and goes behind
  /// the editor's "advanced" fold — including any category name this list does
  /// not know, so a category added server-side shows up as advanced rather
  /// than disappearing.
  ///
  /// Matched on the server's English category names, which are keys in
  /// `PERMISSION_CATEGORIES` and not user-facing text on that side either.
  static const everydayCategories = {
    'Printers',
    'Queue',
    'Archives',
    'Library',
    'Projects',
    'Filaments',
    'Inventory',
    'Smart Plugs',
    'Camera',
    'Maintenance',
    'Stats & History',
    'MakerWorld',
    'WebSocket',
  };

  bool _isEveryday(PermissionCategory c) =>
      everydayCategories.contains(c.name);

  /// The categories a household group is usually made of.
  List<PermissionCategory> get everyday =>
      [for (final c in categories) if (_isEveryday(c)) c];

  /// The rest — administration of the server itself.
  List<PermissionCategory> get advanced =>
      [for (final c in categories) if (!_isEveryday(c)) c];
}
