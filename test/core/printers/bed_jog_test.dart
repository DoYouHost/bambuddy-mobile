import 'package:bambuddy_mobile/core/api/server_version.dart';
import 'package:bambuddy_mobile/core/printers/bed_jog.dart';
import 'package:flutter_test/flutter_test.dart';

BedJogConvention byVersion(String v) =>
    bedJogConventionFor(ServerVersion.tryParse(v));

double? up(String? model, BedJogConvention c) =>
    bedJogDistance(up: true, step: 10, model: model, convention: c);

double? down(String? model, BedJogConvention c) =>
    bedJogDistance(up: false, step: 10, model: model, convention: c);

Map<String, Object?> openApiWith(String description) => {
  'paths': {
    '/api/v1/printers/{printer_id}/bed-jog': {
      'post': {
        'parameters': [
          {'name': 'distance', 'in': 'query', 'description': description},
        ],
      },
    },
  },
};

void main() {
  group('bedJogDependsOnServer mirrors the old A1_MODELS lookup', () {
    test('the six names the old server flipped', () {
      for (final m in ['A1', 'a1 mini', ' A1-MINI ', 'A1MINI', 'N1', 'n2s']) {
        expect(bedJogDependsOnServer(m), isTrue, reason: m);
      }
    });

    test('bed-slingers the old server never flipped', () {
      // A2L and the alternate codes were missing from its list; "A1M" did not
      // survive `.strip().upper()` either.
      for (final m in ['A2L', 'A1M', 'N9', 'A04', 'A11', 'A12', 'X1C', null]) {
        expect(bedJogDependsOnServer(m), isFalse, reason: '$m');
      }
    });
  });

  group('bedJogConventionFor', () {
    test('before the flip shipped (v0.2.4.1)', () {
      expect(byVersion('0.2.4'), BedJogConvention.direct);
      expect(byVersion('0.2.4.0'), BedJogConvention.direct);
    });

    test('the flipping generation, betas of 1.2.5 included', () {
      for (final v in ['0.2.4.1', '0.2.4.9', '0.2.5b3', '1.2.5', '1.2.5.5']) {
        expect(byVersion(v), BedJogConvention.flippedOnA1, reason: v);
      }
    });

    test('from the #1334 release on', () {
      for (final v in ['1.2.5.6', '1.2.5.7', '1.2.6', '1.2.6b2', '1.2.7b1']) {
        expect(byVersion(v), BedJogConvention.direct, reason: v);
      }
    });

    test('1.2.6b1 spans the fix, and an unknown version says nothing', () {
      expect(byVersion('1.2.6b1'), BedJogConvention.unknown);
      expect(byVersion('1.2.6b1-daily.20260919'), BedJogConvention.unknown);
      expect(bedJogConventionFor(null), BedJogConvention.unknown);
    });
  });

  group('bedJogConventionFromOpenApi', () {
    test('the description every flipping server shipped', () {
      final doc = openApiWith(
        'Signed nozzle-bed gap adjustment in mm. Negative = decrease gap '
        '("up" arrow in the UI: bed up on bed-on-Z models, toolhead down '
        'on A1 bed-slingers). Positive = increase gap. The backend '
        'translates this into the right G-code Z sign per printer model.',
      );
      expect(bedJogConventionFromOpenApi(doc), BedJogConvention.flippedOnA1);
    });

    test('the fixed description, and any later rewording of it', () {
      for (final d in [
        'Signed nozzle-bed gap adjustment in mm, identical on every model: '
            'positive opens the gap (more clearance), negative closes it.',
        'Gap in mm.',
      ]) {
        expect(
          bedJogConventionFromOpenApi(openApiWith(d)),
          BedJogConvention.direct,
        );
      }
    });

    test('the pre-v0.2.4.1 description', () {
      final doc = openApiWith(
        'Relative Z distance in mm (positive = bed down / nozzle further '
        'away, negative = bed up)',
      );
      expect(bedJogConventionFromOpenApi(doc), BedJogConvention.direct);
    });

    test('a document that does not list the route, or is not one', () {
      expect(
        bedJogConventionFromOpenApi({'paths': <String, Object?>{}}),
        BedJogConvention.unknown,
      );
      expect(bedJogConventionFromOpenApi({}), BedJogConvention.unknown);
      expect(
        bedJogConventionFromOpenApi('<html>proxy page</html>'),
        BedJogConvention.unknown,
      );
      expect(bedJogConventionFromOpenApi(null), BedJogConvention.unknown);
    });
  });

  group('bedJogDistance', () {
    test('bed-on-Z: up raises the plate and closes the gap, on any server', () {
      for (final c in BedJogConvention.values) {
        expect(up('X1C', c), -10);
        expect(down('X1C', c), 10);
      }
    });

    test('A2L: up lifts the toolhead, on any server', () {
      for (final c in BedJogConvention.values) {
        expect(up('A2L', c), 10);
        expect(down('A2L', c), -10);
      }
    });

    test('A1 on a flipping server keeps what the app always sent', () {
      expect(up('A1 mini', BedJogConvention.flippedOnA1), -10);
      expect(down('A1 mini', BedJogConvention.flippedOnA1), 10);
    });

    test('A1 on a fixed server opens the gap for up', () {
      expect(up('A1', BedJogConvention.direct), 10);
      expect(down('A1', BedJogConvention.direct), -10);
    });

    test('A1 with the convention unknown sends nothing', () {
      expect(up('A1', BedJogConvention.unknown), isNull);
      expect(down('N2S', BedJogConvention.unknown), isNull);
    });

    test('no model is treated as bed-on-Z', () {
      expect(up(null, BedJogConvention.unknown), -10);
    });
  });
}
