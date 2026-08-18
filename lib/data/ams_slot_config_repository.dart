import 'package:dio/dio.dart';

import '../core/ams/slot_configuration.dart';
import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/models/ams_filament_preset.dart';
import '../core/models/k_profile.dart';

/// Everything the "configure AMS slot" flow reads and writes: the three preset
/// sources, the printer-model registry, the slot→preset mapping, and the two
/// commands that change the slot itself.
///
/// Maps [DioException] to [AppApiException] like the other repositories. The one
/// error this class swallows is documented at [cloudFilamentId] — everywhere
/// else a failure is the caller's to handle, including the 401 that simply means
/// "no Bambu Cloud login here".
class AmsSlotConfigRepository {
  AmsSlotConfigRepository(this._dio);

  final Dio _dio;

  /// Filament presets from the user's Bambu Cloud account.
  ///
  /// Throws `AuthException(unauthorized)` when no cloud login exists. That is a
  /// normal state, not a fault: the picker drops to the built-in and imported
  /// tiers and offers the login screen.
  Future<List<AmsFilamentPreset>> cloudFilaments() async {
    final json = await _get<Map<String, dynamic>>(Endpoints.cloudSettings);
    return _presets(json?['filament'], AmsFilamentPreset.fromCloudJson);
  }

  /// The real `filament_id` behind a cloud preset, or null when it cannot be
  /// read.
  ///
  /// Best effort on purpose. The id is an improvement on the one derived from
  /// the setting id — for a user's own preset it is the difference between the
  /// slot resolving to their profile and to the generic it inherits from — but
  /// losing it must not stop the slot being configured, which is what the web
  /// does too.
  Future<String?> cloudFilamentId(String settingId) async {
    try {
      final json = await _get<Map<String, dynamic>>(
          Endpoints.cloudSettingDetail(settingId));
      final id = json?['filament_id'];
      // `base_id` sits right next to it in the response and is deliberately not
      // read: it names the generic this preset inherits from, so falling back
      // to it would resolve the slot to "Generic PLA" (bambuddy #1053).
      return (id is String && id.isNotEmpty) ? id : null;
    } on AppApiException {
      return null;
    }
  }

  /// Bambu's built-in filament table. Needs no cloud login.
  Future<List<AmsFilamentPreset>> builtinFilaments() async {
    final json = await _get<List<dynamic>>(Endpoints.cloudBuiltinFilaments);
    return _presets(json, AmsFilamentPreset.fromBuiltinJson);
  }

  /// Filament presets imported from a slicer bundle.
  Future<List<AmsFilamentPreset>> localFilaments() async {
    final json = await _get<Map<String, dynamic>>(Endpoints.localPresets);
    return _presets(json?['filament'], AmsFilamentPreset.fromLocalJson);
  }

  /// `{"Bambu Lab X1 Carbon": "X1C", …}` — static reference data.
  Future<Map<String, String>> printerModels() async {
    final json = await _get<Map<String, dynamic>>(Endpoints.slicerPrinterModels);
    return {
      for (final entry in (json ?? const {}).entries)
        if (entry.value is String) entry.key: entry.value as String,
    };
  }

  /// Calibration profiles the printer holds for one nozzle size.
  ///
  /// The diameter is a filter, not a hint: profiles calibrated on a 0.4 nozzle
  /// mean nothing to a 0.6 one, and the printer indexes its table by it.
  Future<List<KProfile>> kProfiles(
    int printerId, {
    required String nozzleDiameter,
  }) async {
    final json = await _get<Map<String, dynamic>>(
      Endpoints.printerKProfiles(printerId),
      query: {'nozzle_diameter': nozzleDiameter},
    );
    final raw = json?['profiles'];
    if (raw is! List) return const [];
    return [
      for (final entry in raw)
        if (entry is Map<String, dynamic>) KProfile.fromJson(entry),
    ];
  }

  /// The preset a slot was configured with, or null when it has none.
  Future<SlotPreset?> slotPreset(
    int printerId, {
    required int amsId,
    required int trayId,
  }) async {
    final json = await _get<Map<String, dynamic>>(
        Endpoints.amsSlotPreset(printerId, amsId, trayId));
    // The route answers a bare `null` for an unmapped slot, which Dio hands
    // back as no data at all.
    return json == null ? null : SlotPreset.fromJson(json);
  }

  /// Remember which preset a slot was given. Parameters go in the query, not a
  /// body — the route declares them as bare arguments.
  Future<void> saveSlotPreset(
    int printerId, {
    required int amsId,
    required int trayId,
    required AmsFilamentPreset preset,
    required String presetName,
  }) async {
    try {
      await _dio.put<dynamic>(
        Endpoints.amsSlotPreset(printerId, amsId, trayId),
        queryParameters: <String, dynamic>{
          'preset_id': preset.pickerId,
          'preset_name': presetName,
          'preset_source': preset.sourceKey,
        },
      );
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// Write a filament configuration into a slot. Ids are local to the unit;
  /// the external spool is unit 255, slot 0 (Ext-L) or 1 (Ext-R).
  Future<void> configureSlot(
    int printerId, {
    required int amsId,
    required int trayId,
    required SlotConfiguration configuration,
  }) =>
      _post(Endpoints.amsSlotConfigure(printerId, amsId, trayId),
          query: configuration.toQuery());

  /// Clear a slot's filament configuration. Also drops the saved mapping
  /// server-side, so [slotPreset] answers null afterwards.
  Future<void> resetSlot(
    int printerId, {
    required int amsId,
    required int trayId,
  }) =>
      _post(Endpoints.amsSlotReset(printerId, amsId, trayId));

  Future<T?> _get<T>(String path, {Map<String, dynamic>? query}) async {
    try {
      final res = await _dio.get<T>(path, queryParameters: query);
      return res.data;
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  Future<void> _post(String path, {Map<String, dynamic>? query}) async {
    try {
      await _dio.post<dynamic>(path, queryParameters: query);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}

/// Read a list of presets, skipping entries that are not objects and those a
/// tier left without an id — an unnameable preset cannot be selected anyway.
List<AmsFilamentPreset> _presets(
  Object? raw,
  AmsFilamentPreset Function(Map<String, dynamic>) parse,
) {
  if (raw is! List) return const [];
  return [
    for (final entry in raw)
      if (entry is Map<String, dynamic>) parse(entry),
  ].where((p) => p.id.isNotEmpty).toList();
}
