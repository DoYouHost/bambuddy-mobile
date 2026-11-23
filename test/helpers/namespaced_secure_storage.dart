import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';

/// In-memory secure storage that keeps each `storageNamespace` in a map of its
/// own, as the Android plugin keeps each in its own preferences file and
/// Keystore alias (`FlutterSecureStoragePlugin.getOrCreateStorage`, "ns:" +
/// namespace). `deleteAll` empties only the namespace it was called on.
class NamespacedSecureStorage extends FlutterSecureStoragePlatform {
  /// Installs a fresh one as the plugin's platform and returns it.
  static NamespacedSecureStorage install() {
    final storage = NamespacedSecureStorage._();
    FlutterSecureStoragePlatform.instance = storage;
    return storage;
  }

  NamespacedSecureStorage._();

  final namespaces = <String, Map<String, String>>{};

  Map<String, String> _of(Map<String, String> options) =>
      namespaces.putIfAbsent(options['storageNamespace'] ?? '', () => {});

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async => _of(options).containsKey(key);

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async => _of(options).remove(key);

  @override
  Future<void> deleteAll({required Map<String, String> options}) async =>
      _of(options).clear();

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async => _of(options)[key];

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async => Map.of(_of(options));

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async => _of(options)[key] = value;
}
