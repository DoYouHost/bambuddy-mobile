import 'package:bambuddy_mobile/core/models/process_option.dart';
import 'package:bambuddy_mobile/core/slicer/filament_slot_options.dart';
import 'package:flutter_test/flutter_test.dart';

ProcessOption _option(String key, {OptionType type = OptionType.coInt}) =>
    ProcessOption(key: key, type: type, mode: OptionMode.simple, label: key);

void main() {
  group('namesFilamentSlot', () {
    test('is true for every key the server panel treats the same way', () {
      // The set is copied from `SlicerSettingsPanel.tsx`; if it drifts, one of
      // the two front ends offers a slot picker the other does not.
      for (final key in filamentSlotOptionKeys) {
        expect(namesFilamentSlot(_option(key)), isTrue, reason: key);
      }
      expect(filamentSlotOptionKeys, hasLength(8));
    });

    test('is false for the wipe tower, whose 0 means something else', () {
      // "Whichever is available, preferring non-soluble" is not "the region's own
      // filament", so it must not be offered as "Default".
      expect(namesFilamentSlot(_option('wipe_tower_filament')), isFalse);
    });

    test('is false for an ordinary integer option', () {
      expect(namesFilamentSlot(_option('wall_loops')), isFalse);
    });

    test('is false when one of the keys stops being a plain int', () {
      // A re-vendor can change a type. The generic control for whatever it became
      // is a safer answer than a slot dropdown over a value that is no longer a
      // slot index.
      expect(
        namesFilamentSlot(_option('support_filament', type: OptionType.coEnum)),
        isFalse,
      );
    });
  });

  group('FilamentSlotChoice', () {
    test('is used by the plate unless told otherwise', () {
      // Marking is only ever honest when the server discriminated, so the
      // no-argument reading has to be the unmarked one.
      expect(const FilamentSlotChoice(slot: 1, label: 'PLA').unused, isFalse);
    });
  });
}
