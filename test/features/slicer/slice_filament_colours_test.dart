import 'package:bambuddy_mobile/core/models/filament_requirement.dart';
import 'package:bambuddy_mobile/core/models/slicer_preset.dart';
import 'package:bambuddy_mobile/features/slicer/slice_filament_colours.dart';
import 'package:bambuddy_mobile/features/slicer/slice_providers.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the slice request records as each slot's colour.
///
/// The slicer has no colour of its own to fall back on but a compiled-in green,
/// so whatever this produces is what the sliced file claims is loaded — and what
/// the print dialog then compares against the AMS slot.
const _pla = SlicerPreset(source: 'local', id: '1', name: 'Bambu PLA Basic');
const _petg = SlicerPreset(source: 'local', id: '2', name: 'Bambu PETG HF');

OwnedFilament _owned(String name, String? color, {String material = 'PLA'}) =>
    (name: name, material: material, color: color);

void main() {
  group('one slot', () {
    test('takes the colour of the spool behind the picked preset', () {
      expect(
        sliceSlotColour(
          picked: _pla,
          owned: [_owned('Bambu PLA Basic', 'ff0000ff')],
          requirement: null,
        ),
        '#FF0000',
      );
    });

    test('drops the alpha the inventory writes', () {
      // `rgba` is hex8; a transparency the spool never had would be a claim
      // about the material, not about its colour.
      expect(
        sliceSlotColour(
          picked: _pla,
          owned: [_owned('Bambu PLA Basic', '11223380')],
          requirement: null,
        ),
        '#112233',
      );
    });

    test('is empty when no owned spool carries that preset', () {
      // Empty is how the server is told to fall back for this slot alone.
      expect(
        sliceSlotColour(
          picked: _petg,
          owned: [_owned('Bambu PLA Basic', 'ff0000ff')],
          requirement: null,
        ),
        '',
      );
    });

    test('is empty when nothing is picked yet', () {
      expect(sliceSlotColour(picked: null, owned: [], requirement: null), '');
    });

    test('is empty when the spool has no colour at all', () {
      expect(
        sliceSlotColour(
          picked: _pla,
          owned: [_owned('Bambu PLA Basic', null)],
          requirement: null,
        ),
        '',
      );
    });

    test('skips a spool whose colour is unparseable for one that has one', () {
      expect(
        sliceSlotColour(
          picked: _pla,
          owned: [
            _owned('Bambu PLA Basic', 'nonsense'),
            _owned('Bambu PLA Basic', '00ff00ff'),
          ],
          requirement: null,
        ),
        '#00FF00',
      );
    });

    test('picks the shelf colour closest to what the plate was designed with',
        () {
      // One preset covers every spool of that filament, so the name alone does
      // not name a colour — the plate is the only thing that says which of them
      // the user meant.
      expect(
        sliceSlotColour(
          picked: _pla,
          owned: [
            _owned('Bambu PLA Basic', 'ffffffff'),
            _owned('Bambu PLA Basic', '0000f0ff'),
            _owned('Bambu PLA Basic', '000000ff'),
          ],
          requirement: const FilamentRequirement(slotId: 1, color: '#0000FF'),
        ),
        '#0000F0',
      );
    });

    test('falls back to the first match when the plate named no colour', () {
      expect(
        sliceSlotColour(
          picked: _pla,
          owned: [
            _owned('Bambu PLA Basic', '010203ff'),
            _owned('Bambu PLA Basic', '040506ff'),
          ],
          requirement: const FilamentRequirement(slotId: 1),
        ),
        '#010203',
      );
    });
  });

  group('the whole array', () {
    test('is positional, one entry per picked slot', () {
      expect(
        sliceFilamentColours(
          picked: [_pla, _petg],
          owned: [
            _owned('Bambu PLA Basic', 'ff0000ff'),
            _owned('Bambu PETG HF', '0000ffff', material: 'PETG'),
          ],
          requirements: const [],
        ),
        ['#FF0000', '#0000FF'],
      );
    });

    test('keeps an unanswered slot as a hole rather than shortening the list',
        () {
      // Shortening would shift every slot after it onto the wrong colour.
      expect(
        sliceFilamentColours(
          picked: [_pla, _petg],
          owned: [_owned('Bambu PETG HF', '0000ffff', material: 'PETG')],
          requirements: const [],
        ),
        ['', '#0000FF'],
      );
    });

    test('is empty when no slot has an answer, so the key can be dropped', () {
      // A request with nothing to say has to stay byte-identical to one from
      // before the field existed.
      expect(
        sliceFilamentColours(
          picked: [_pla, _petg],
          owned: const [],
          requirements: const [],
        ),
        isEmpty,
      );
    });

    test('tolerates fewer requirements than slots', () {
      // The requirement list is what the server read out of the plate; a slot
      // it did not describe still has to reach the array.
      expect(
        sliceFilamentColours(
          picked: [_pla, _pla],
          owned: [_owned('Bambu PLA Basic', 'ff0000ff')],
          requirements: const [FilamentRequirement(slotId: 1, color: '#FF0000')],
        ),
        ['#FF0000', '#FF0000'],
      );
    });
  });
}
