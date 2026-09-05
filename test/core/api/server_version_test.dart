import 'package:bambuddy_mobile/core/api/server_version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ServerVersion parse(String s) {
    final v = ServerVersion.tryParse(s);
    expect(v, isNotNull, reason: 'did not parse: $s');
    return v!;
  }

  group('parsing', () {
    test('three components', () {
      final v = parse('1.2.5');
      expect([v.major, v.minor, v.patch, v.micro], [1, 2, 5, 0]);
      expect(v.isPrerelease, isFalse);
    });

    test('four components — the old 0.2.x numbering', () {
      final v = parse('0.2.4.9');
      expect([v.major, v.minor, v.patch, v.micro], [0, 2, 4, 9]);
      expect(v.isPrerelease, isFalse);
    });

    test('a v prefix', () {
      expect(parse('v1.2.5.1').micro, 1);
    });

    test('beta', () {
      final v = parse('1.2.6b1');
      expect([v.major, v.minor, v.patch], [1, 2, 6]);
      expect(v.isPrerelease, isTrue);
      expect(v.prereleaseNum, 1);
    });

    test('a daily build — the suffix is stripped as the server strips it', () {
      final v = parse('1.2.6b1-daily.20260729');
      expect([v.major, v.minor, v.patch], [1, 2, 6]);
      expect(v.prereleaseNum, 1);
      expect(v.isPrerelease, isTrue);
      expect(v.raw, '1.2.6b1-daily.20260729',
          reason: 'the log has to carry what the server actually said');
    });

    test('rc and alpha count too', () {
      expect(parse('1.3.0rc2').prereleaseNum, 2);
      expect(parse('1.3.0alpha1').isPrerelease, isTrue);
    });

    test('a non-version → null, not an exception', () {
      for (final junk in [null, '', '   ', 'unknown', '1', '1.2', '<html>']) {
        expect(ServerVersion.tryParse(junk), isNull, reason: 'input: $junk');
      }
    });
  });

  group('comparison', () {
    test('component order', () {
      expect(parse('1.2.5') < parse('1.2.6'), isTrue);
      expect(parse('0.2.4.9') < parse('1.2.5'), isTrue);
      expect(parse('1.2.5') < parse('1.2.5.1'), isTrue);
    });

    test('a release beats its own beta', () {
      expect(parse('1.2.5') >= parse('1.2.5b7'), isTrue);
      expect(parse('1.2.5b7') < parse('1.2.5'), isTrue);
    });

    test('a later beta beats an earlier one', () {
      expect(parse('1.2.5b10') >= parse('1.2.5b7'), isTrue);
    });

    test("the next version's beta beats the current release", () {
      expect(parse('1.2.6b1') >= parse('1.2.5'), isTrue);
    });
  });

  group('tri-state calibrations', () {
    test('from 1.2.5 upward', () {
      for (final v in ['1.2.5', '1.2.5.1', '1.2.6', '2.0.0']) {
        expect(parse(v).supports(ServerFeature.triStateCalibration), isTrue, reason: v);
      }
    });

    test('the whole 0.2.x line, not yet', () {
      for (final v in ['0.2.4.9', '0.2.4.8', '0.2.3', '0.1.5']) {
        expect(parse(v).supports(ServerFeature.triStateCalibration), isFalse, reason: v);
      }
    });

    test('a 1.2.5 beta counts as supporting', () {
      // The change landed in that cycle; reading a beta as the older shape
      // would send a boolean where the user asked for auto.
      expect(parse('1.2.5b1').supports(ServerFeature.triStateCalibration), isTrue);
    });

    test('0.2.5bN comes out as "not supported" — and that is this method\'s limit',
        () {
      // bambuddy renumbered the 0.2.5 cycle to 1.2.5 partway through, so
      // `0.2.5b2` (the version our own server reports) is a beta of EXACTLY the
      // release that introduced the tri-state — and still sorts below 1.2.5 in
      // every sensible ordering. No comparison of those two strings can say
      // whether this particular beta is before the change or after it.
      //
      // What is left is a careful "no": sending a string to a server that does
      // not know it is a 422, while a missing auto option is only a missing
      // feature. The real answer comes from observing what the server replies —
      // see QueueRepository.supports(ServerFeature.triStateCalibration) and its tests.
      expect(parse('0.2.5b2').supports(ServerFeature.triStateCalibration), isFalse);
      expect(parse('0.2.5b2') < parse('1.2.5'), isTrue);
    });
  });

  group('version → capability map', () {
    test('every capability has a row — a missing one silently disables it', () {
      // supports() answers false for an unmapped feature, so a forgotten row
      // does not fail to compile — it quietly takes the feature away from
      // everybody. This test is the only thing that catches it.
      for (final f in ServerFeature.values) {
        expect(ServerVersion.introducedIn[f], isNotNull,
            reason: 'no version threshold for $f');
      }
    });

    test('supports() reads the threshold from the map, not a separate compare', () {
      final v125 = parse('1.2.5.2');
      final v126 = parse('1.2.6');

      // Tri-state arrived in 1.2.5 and everything else in 1.2.6 — the only
      // difference between these two versions in the whole table.
      expect(v125.supports(ServerFeature.triStateCalibration), isTrue);
      expect(v126.supports(ServerFeature.triStateCalibration), isTrue);

      for (final f in const [
        ServerFeature.chamberTemp65,
        ServerFeature.crossModelVariants,
        ServerFeature.sliceLayoutOptions,
        ServerFeature.processOverrides,
        ServerFeature.usersSlimListing,
        ServerFeature.printLogCostEnergy,
        ServerFeature.labelStartingPosition,
      ]) {
        expect(v125.supports(f), isFalse, reason: '$f absent in 1.2.5');
        expect(v126.supports(f), isTrue, reason: '$f present in 1.2.6');
      }
    });
  });

  group('1.2.6 gates', () {
    test('chamber ceiling: 60 up to 1.2.5.x, 65 from 1.2.6', () {
      // The server raised MAX_CHAMBER_TEMP_C from 60 to 65 (commit b04664c6),
      // and the bound is a Query(le=…) — an older server answers 422 rather
      // than clamping.
      expect(parse('1.2.5.2').chamberMaxTargetC, 60);
      expect(parse('1.2.6').chamberMaxTargetC, 65);
    });

    test('a 1.2.6 beta counts as supporting — the features landed in that cycle',
        () {
      // 1.2.6b1 is the release these changes actually shipped in (#671 and the
      // raised ceiling both live there), so reading a beta as the older
      // contract would take features away from a server that has them.
      final beta = parse('1.2.6b1');
      expect(beta.chamberMaxTargetC, 65);
      expect(beta.supports(ServerFeature.crossModelVariants), isTrue);
      expect(beta.supports(ServerFeature.sliceLayoutOptions), isTrue);
      expect(beta.supports(ServerFeature.processOverrides), isTrue);
    });

    test('a daily build of the beta counts too', () {
      expect(parse('1.2.6b1-daily.20260809').chamberMaxTargetC, 65);
    });

    test('an older server gets none of the gates', () {
      final old = parse('1.2.5.2');
      expect(old.supports(ServerFeature.crossModelVariants), isFalse);
      expect(old.supports(ServerFeature.sliceLayoutOptions), isFalse);
      expect(old.supports(ServerFeature.processOverrides), isFalse);
    });
  });
}
