import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_providers.dart';
import 'package:flutter_test/flutter_test.dart';

/// Matching an AMS slot's RFID tag against the shelf. It decides whether the
/// slot sheet offers to register the spool or to pick the one that is already
/// there — and the server's from-slot route never deduplicates, so a miss here
/// costs a second row for the same physical spool.
void main() {
  InventoryState shelf(List<Spool> spools) => InventoryState(spools: spools);

  const byUid = Spool(id: 1, material: 'PLA', tagUid: 'A1B2C3D4E5F60708');
  const byUuid = Spool(
    id: 2,
    material: 'PETG',
    trayUuid: 'FFEEDDCCBBAA99887766554433221100',
  );
  const untagged = Spool(id: 3, material: 'ABS');

  test('finds a spool by its tag UID whatever case the printer reports',
      () {
    final state = shelf([untagged, byUid]);

    expect(state.spoolForTag(tagUid: 'a1b2c3d4e5f60708')?.id, 1);
    expect(state.spoolForTag(tagUid: 'A1B2C3D4E5F60708')?.id, 1);
  });

  test('the tray UUID wins over the tag UID', () {
    // Only the UUID survives re-spooling the filament onto another core, which
    // is why the server tries it first.
    const both = Spool(
      id: 9,
      material: 'PLA',
      tagUid: 'A1B2C3D4E5F60708',
      trayUuid: 'FFEEDDCCBBAA99887766554433221100',
    );
    final state = shelf([byUid, both]);

    expect(
      state
          .spoolForTag(
            tagUid: 'A1B2C3D4E5F60708',
            trayUuid: 'ffeeddccbbaa99887766554433221100',
          )
          ?.id,
      9,
    );
  });

  test('a tag no spool carries is a miss, not the first untagged spool', () {
    final state = shelf([untagged, byUid, byUuid]);

    expect(state.spoolForTag(tagUid: '0011223344556677'), isNull);
  });

  test('no tag at all matches nothing, including the untagged spools', () {
    // A slot without a tag must never resolve to a spool: it would hide the
    // registration affordance behind an unrelated row.
    final state = shelf([untagged, byUid]);

    expect(state.spoolForTag(), isNull);
    expect(state.spoolForTag(tagUid: '', trayUuid: ''), isNull);
    expect(state.spoolForTag(tagUid: '   '), isNull);
  });

  test('an empty shelf answers null rather than throwing', () {
    expect(shelf(const []).spoolForTag(tagUid: 'A1B2C3D4E5F60708'), isNull);
  });

  test('separators in the reported tag do not stop the match', () {
    final state = shelf([byUid]);

    expect(state.spoolForTag(tagUid: 'a1:b2:c3:d4:e5:f6:07:08')?.id, 1);
  });
}
