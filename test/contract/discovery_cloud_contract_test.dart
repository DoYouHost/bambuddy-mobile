import 'package:bambuddy_mobile/core/models/ams_filament_preset.dart';
import 'package:bambuddy_mobile/core/models/cloud_auth.dart';
import 'package:bambuddy_mobile/core/models/discovery.dart';
import 'package:bambuddy_mobile/core/models/firmware.dart';
import 'package:bambuddy_mobile/core/models/makerworld.dart';
import 'package:bambuddy_mobile/data/ams_slot_config_repository.dart';
import 'package:bambuddy_mobile/data/cloud_repository.dart';
import 'package:bambuddy_mobile/data/discovery_repository.dart';
import 'package:bambuddy_mobile/data/firmware_repository.dart';
import 'package:bambuddy_mobile/data/makerworld_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';

void main() {
  group('discovery, cloud and makerworld contract', skip: contractSkipReason, () {
    late Dio dio;
    late DiscoveryRepository discoveryRepo;
    late CloudRepository cloudRepo;
    late MakerWorldRepository makerworldRepo;
    late FirmwareRepository firmwareRepo;
    late AmsSlotConfigRepository slotConfigRepo;

    setUpAll(() async {
      dio = await authenticatedDio();
      discoveryRepo = DiscoveryRepository(dio);
      cloudRepo = CloudRepository(dio);
      makerworldRepo = MakerWorldRepository(dio);
      firmwareRepo = FirmwareRepository(dio);
      slotConfigRepo = AmsSlotConfigRepository(dio);
    });

    test('GET /discovery/info and /discovery/scan/status decode', () async {
      final info = await discoveryRepo.info();
      expect(info, isA<DiscoveryInfo>());
      expect(info.subnets, isA<List<String>>());

      final scanStatus = await discoveryRepo.scanStatus();
      expect(scanStatus, isA<ScanStatus>());

      final printers = await discoveryRepo.discoveredPrinters();
      expect(printers, isA<List<DiscoveredPrinter>>());
    });

    test('GET /cloud/status decodes into CloudAuthStatus', () async {
      final status = await cloudRepo.status();
      expect(status, isA<CloudAuthStatus>());
    });

    test('GET /cloud/builtin-filaments decodes into AmsFilamentPreset list', () async {
      final builtins = await slotConfigRepo.builtinFilaments();
      expect(builtins, isA<List<AmsFilamentPreset>>());
      for (final f in builtins) {
        expect(f.id, isNotEmpty);
        expect(f.name, isNotEmpty);
      }
    });

    test('GET /makerworld/status decodes into MakerWorldStatus', () async {
      final status = await makerworldRepo.status();
      expect(status, isA<MakerWorldStatus>());
    });

    test('GET /firmware/updates decodes into FirmwareUpdatesResponse', () async {
      final updates = await firmwareRepo.fetchUpdates();
      expect(updates, isA<FirmwareUpdatesResponse>());
      expect(updates.updates, isA<List<FirmwareUpdateInfo>>());
    });
  });
}
