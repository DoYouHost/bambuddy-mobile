import 'json_utils.dart';

/// What an API key is allowed to do. The server gates a key on these flags
/// rather than on permissions (`_APIKEY_SCOPE_BY_PERMISSION`,
/// `backend/app/core/auth.py:64`): each maps to a slice of the permission
/// catalog, and everything administrative is outside all of them — a key can
/// never manage users, groups, keys or settings.
enum ApiKeyScope {
  readStatus('can_read_status'),
  queue('can_queue'),
  controlPrinter('can_control_printer'),
  manageLibrary('can_manage_library'),
  manageInventory('can_manage_inventory'),
  manageMaintenance('can_manage_maintenance'),
  manageArchives('can_manage_archives'),
  manageProjects('can_manage_projects'),

  /// Reads `/cloud/*` as the account that created the key. Refused at creation
  /// on a server with authentication off — there is no per-user cloud token to
  /// read against (`backend/app/api/routes/api_keys.py:47`).
  accessCloud('can_access_cloud'),

  /// The one narrow door into settings: `POST /settings/electricity-price`
  /// (`core/auth.py:338`).
  updateEnergyCost('can_update_energy_cost');

  const ApiKeyScope(this.wire);

  /// The field name on the wire.
  final String wire;
}

/// A key as `GET /api-keys/` sends it (`APIKeyResponse`,
/// `backend/app/schemas/api_key.py:44`) — never the key itself, only enough to
/// recognise it.
class ApiKey {
  const ApiKey({
    required this.id,
    required this.name,
    required this.keyPrefix,
    this.userId,
    this.scopes = const {},
    this.printerIds,
    this.enabled = true,
    this.lastUsed,
    this.createdAt,
    this.expiresAt,
  });

  factory ApiKey.fromJson(Map<String, dynamic> json) => ApiKey(
        id: toInt(json['id']),
        name: toStringOrNull(json['name']) ?? '',
        keyPrefix: toStringOrNull(json['key_prefix']) ?? '',
        userId: toIntOrNull(json['user_id']),
        scopes: {
          for (final scope in ApiKeyScope.values)
            if (json[scope.wire] == true) scope,
        },
        // Null means every printer; an empty list would mean none.
        printerIds: json['printer_ids'] == null
            ? null
            : [
                for (final id in json['printer_ids'] as List) toInt(id),
              ],
        enabled: json['enabled'] != false,
        lastUsed: dateTimeFromJson(json['last_used']),
        createdAt: dateTimeFromJson(json['created_at']),
        expiresAt: dateTimeFromJson(json['expires_at']),
      );

  final int id;
  final String name;

  /// First characters of the key — how a row is matched to the key someone
  /// pasted somewhere, since the key itself is gone.
  final String keyPrefix;

  /// The account that created it. Null on a key made before the server tracked
  /// ownership, which is also why such a key cannot reach the cloud routes.
  final int? userId;

  final Set<ApiKeyScope> scopes;

  /// Printers this key is confined to; null = all of them.
  final List<int>? printerIds;

  final bool enabled;
  final DateTime? lastUsed;
  final DateTime? createdAt;
  final DateTime? expiresAt;

  bool get isLegacy => userId == null;

  /// Whether the server would already refuse it. The list still shows it —
  /// "why did this stop working" is the question it answers.
  bool isExpired(DateTime now) =>
      expiresAt != null && expiresAt!.isBefore(now);
}

/// The one moment the full key exists in the app: the answer to `POST
/// /api-keys/` (`APIKeyCreateResponse`, `schemas/api_key.py:69`). Never
/// stored, never logged — the server cannot show it again.
class CreatedApiKey {
  const CreatedApiKey({required this.key, required this.apiKey});

  factory CreatedApiKey.fromJson(Map<String, dynamic> json) => CreatedApiKey(
        key: toStringOrNull(json['key']) ?? '',
        apiKey: ApiKey.fromJson(json),
      );

  final String key;
  final ApiKey apiKey;
}

/// Body for `POST /api-keys/` (`APIKeyCreate`, `schemas/api_key.py:6`).
///
/// Every flag is sent explicitly: the server's defaults are generous (queue,
/// library, inventory, maintenance, archives and projects all default to
/// true), so a form that omitted an unticked box would hand out more than it
/// showed.
class ApiKeyCreateInput {
  const ApiKeyCreateInput({
    required this.name,
    this.scopes = const {},
    this.printerIds,
    this.expiresAt,
  });

  final String name;
  final Set<ApiKeyScope> scopes;
  final List<int>? printerIds;
  final DateTime? expiresAt;

  Map<String, dynamic> toJson() => {
        'name': name,
        for (final scope in ApiKeyScope.values) scope.wire: scopes.contains(scope),
        if (printerIds != null) 'printer_ids': printerIds,
        if (expiresAt != null) 'expires_at': expiresAt!.toUtc().toIso8601String(),
      };
}

/// Body for `PATCH /api-keys/{id}` (`APIKeyUpdate`, `schemas/api_key.py:26`).
/// Omitted means unchanged, as everywhere else.
class ApiKeyUpdateInput {
  const ApiKeyUpdateInput({
    this.name,
    this.scopes,
    this.printerIds,
    this.clearPrinterIds = false,
    this.enabled,
    this.expiresAt,
  });

  final String? name;

  /// The whole set, or null to leave every flag alone.
  final Set<ApiKeyScope>? scopes;

  final List<int>? printerIds;

  /// Lifting a printer restriction means sending an explicit null, which
  /// [printerIds] alone cannot express.
  final bool clearPrinterIds;

  final bool? enabled;
  final DateTime? expiresAt;

  bool get isEmpty =>
      name == null &&
      scopes == null &&
      printerIds == null &&
      !clearPrinterIds &&
      enabled == null &&
      expiresAt == null;

  Map<String, dynamic> toJson() => {
        if (name != null) 'name': name,
        if (scopes != null)
          for (final scope in ApiKeyScope.values)
            scope.wire: scopes!.contains(scope),
        if (clearPrinterIds)
          'printer_ids': null
        else if (printerIds != null)
          'printer_ids': printerIds,
        if (enabled != null) 'enabled': enabled,
        if (expiresAt != null) 'expires_at': expiresAt!.toUtc().toIso8601String(),
      };
}
