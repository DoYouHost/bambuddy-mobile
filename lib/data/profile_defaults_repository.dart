import 'package:app_util/app_util.dart';
import 'package:dio/dio.dart';

import '../core/api/endpoints.dart';
import '../core/api/observed_capability.dart';
import '../core/api/server_version.dart';
import '../core/api/server_version_service.dart';
import '../core/models/profile_default.dart';
import 'inventory_source.dart';

/// Profile defaults (server #1326): what a new spool of a product starts with.
///
/// The server applies a default to every spool it creates, so this class only
/// reads, saves, deletes and applies them. List, resolve, save and delete are
/// the same routes in both inventory modes; only [apply] depends on which one
/// is live.
class ProfileDefaultsRepository {
  ProfileDefaultsRepository(this._dio, this._backend, [this._serverVersion]);

  final Dio _dio;

  /// Which inventory is live, asked at the moment of an apply.
  final Future<InventoryBackend> Function() _backend;

  /// Answers [capability] until a route has.
  final ServerVersionService? _serverVersion;

  /// Whether the server has the route family at all.
  late final capability = ObservedCapability(
    ServerFeature.profileDefaults,
    _serverVersion,
  );

  /// Every default, ordered by product. A 404 or a 403 answers with an empty
  /// list: the latch has recorded why, and what reads this is additive.
  Future<List<ProfileDefault>> list() => capability.watching(
    () async {
      final res = await _dio.get<List<dynamic>>(
        Endpoints.inventoryProfileDefaults,
      );
      return parseJsonList(res.data, ProfileDefault.fromJson);
    },
    absent: () => const [],
    observing: treat404AsAbsent,
  );

  /// What a new spool of [product] starts with, or null when it has no default
  /// — and null as well on a server without the route, where the form simply
  /// has nothing to fill in.
  Future<ResolvedProfileDefault?> resolve(ProfileProduct product) =>
      capability.watching(
        () async {
          final res = await _dio.get<dynamic>(
            Endpoints.inventoryProfileDefaultsResolve,
            queryParameters: {
              'material': product.material.trim(),
              'brand': product.brand.trim(),
              'subtype': product.subtype.trim(),
              'color_name': product.colorName.trim(),
            },
          );
          final body = res.data;
          return body is Map
              ? ResolvedProfileDefault.fromJson(asJsonRecord(body))
              : null;
        },
        absent: () => null,
        observing: treat404AsAbsent,
      );

  /// Creates or **replaces** the default for the draft's product: the body is
  /// everything the default holds, so a caller that cannot show something must
  /// send back what the server has (see [ProfileDefault.kProfiles]).
  ///
  /// The writes settle nothing: their 403 is a missing `inventory:update`, and
  /// taking it for "no defaults here" would hide a list the session may read.
  Future<ProfileDefault> save(ProfileDefaultDraft draft) =>
      capability.watching(observing: const {}, () async {
        final res = await _dio.put<Map<String, dynamic>>(
          Endpoints.inventoryProfileDefaults,
          data: draft.toJson(),
        );
        return ProfileDefault.fromJson(res.data ?? const {});
      });

  /// Spools that already got its profiles keep them. A 403 here also means the
  /// default holds K profiles of printers the caller cannot access.
  Future<void> delete(int id) => capability.watching(
    observing: const {},
    () => _dio.delete<dynamic>(Endpoints.inventoryProfileDefault(id)),
  );

  /// Fills in what active spools of the default's product do not have yet,
  /// never overwriting. Returns how many spools it changed.
  Future<int> apply(int id) =>
      capability.watching(observing: const {}, () async {
        final path = await _backend() == InventoryBackend.spoolman
            ? Endpoints.spoolmanProfileDefaultApply(id)
            : Endpoints.inventoryProfileDefaultApply(id);
        final res = await _dio.post<Map<String, dynamic>>(path);
        return toInt(res.data?['updated']);
      });
}
