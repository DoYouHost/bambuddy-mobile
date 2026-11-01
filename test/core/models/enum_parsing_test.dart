import 'package:bambuddy_mobile/core/models/archive.dart';
import 'package:bambuddy_mobile/core/models/json_utils.dart';
import 'package:bambuddy_mobile/core/models/pipeline_run.dart';
import 'package:bambuddy_mobile/core/models/scheduled_drying.dart';
import 'package:bambuddy_mobile/core/models/slicer_pipeline.dart';
import 'package:bambuddy_mobile/core/models/spool_label.dart';
import 'package:bambuddy_mobile/core/models/wallet.dart';
import 'package:flutter_test/flutter_test.dart';

enum _Sample {
  alpha('a_wire'),
  beta('b_wire');

  const _Sample(this.wire);

  final String wire;
}

void main() {
  group('enumByName', () {
    final cases = <String, (Object?, _Sample?)>{
      'known': ('alpha', _Sample.alpha),
      'unknown': ('gamma', null),
      'null': (null, null),
      'int': (1, null),
      'empty': ('', null),
      'wrong case': ('Alpha', null),
      'padded': (' alpha', null),
      'the wire spelling': ('a_wire', null),
    };
    cases.forEach((label, c) {
      test(label, () => expect(enumByName(_Sample.values, c.$1), c.$2));
    });
  });

  group('enumByWire', () {
    final cases = <String, (Object?, _Sample?)>{
      'known': ('b_wire', _Sample.beta),
      'unknown': ('gamma', null),
      'null': (null, null),
      'int': (1, null),
      'empty': ('', null),
      'wrong case': ('B_WIRE', null),
      'padded': ('b_wire ', null),
      'the enum name': ('beta', null),
    };
    cases.forEach((label, c) {
      test(label, () {
        expect(enumByWire(_Sample.values, c.$1, (s) => s.wire), c.$2);
      });
    });
  });

  // Every enum that carries a wire form: parse(wire(v)) == v, so a member added
  // without a distinct spelling fails here.
  group('wire round trip', () {
    void roundTrip<T extends Enum>(
      String label,
      List<T> values,
      Object? Function(T) wire,
      T Function(Object? raw) parse, {
      Set<T> withoutWire = const {},
    }) {
      test(label, () {
        for (final v in values.where((v) => !withoutWire.contains(v))) {
          expect(parse(wire(v)), v, reason: '$v');
        }
      });
    }

    roundTrip(
      'SpoolLabelField',
      SpoolLabelField.values,
      (v) => v.wire,
      (r) => SpoolLabelField.fromWire(r)!,
    );
    roundTrip(
      'SpoolLabelFormat',
      SpoolLabelFormat.values,
      (v) => v.name,
      SpoolLabelFormat.fromName,
    );
    roundTrip(
      'PrintVerdict',
      PrintVerdict.values,
      (v) => v.wire,
      (r) => PrintVerdict.fromWire(r)!,
    );
    roundTrip(
      'DryingWaitReason',
      DryingWaitReason.values,
      (v) => v.wire,
      (r) => DryingWaitReason.fromWire(r as String?)!,
      withoutWire: {DryingWaitReason.unknown},
    );
    roundTrip(
      'WalletTransactionType',
      WalletTransactionType.values,
      (v) => v.wire,
      WalletTransactionType.parse,
    );
    roundTrip(
      'EligibilityIssueKind',
      EligibilityIssueKind.values,
      (v) => v.wire,
      (r) => EligibilityIssueKind.parse(r as String?),
    );
    roundTrip(
      'PipelineRunStatus',
      PipelineRunStatus.values,
      (v) => v.wire,
      (r) => PipelineRunStatus.parse(r as String?),
      withoutWire: {PipelineRunStatus.unknown},
    );
    roundTrip(
      'PipelineJobStatus',
      PipelineJobStatus.values,
      (v) => v.wire,
      (r) => PipelineJobStatus.parse(r as String?),
    );
    roundTrip(
      'PipelineTargetKind',
      PipelineTargetKind.values,
      (v) => v.wire,
      (r) => PipelineTargetKind.parse(r as String?),
    );
    roundTrip(
      'FanoutStrategy',
      FanoutStrategy.values,
      (v) => v.wire,
      (r) => FanoutStrategy.parse(r as String?),
    );
  });

  group('what each parser falls back to', () {
    test('nothing for a missing or unknown verdict / label field', () {
      expect(PrintVerdict.fromWire(null), isNull);
      expect(PrintVerdict.fromWire('GOOD'), isNull);
      expect(PrintVerdict.fromWire(1), isNull);
      expect(SpoolLabelField.fromWire(''), isNull);
    });

    test('label format falls back to pdf', () {
      expect(SpoolLabelFormat.fromName('PNG'), SpoolLabelFormat.pdf);
      expect(SpoolLabelFormat.fromName(null), SpoolLabelFormat.pdf);
      expect(SpoolLabelFormat.fromName(2), SpoolLabelFormat.pdf);
    });

    test('drying wait reason: null for none, unknown for a new token', () {
      expect(DryingWaitReason.fromWire(null), isNull);
      expect(DryingWaitReason.fromWire(''), isNull);
      expect(DryingWaitReason.fromWire('brand_new'), DryingWaitReason.unknown);
    });

    test('wallet kind falls back to other', () {
      for (final raw in [null, '', 'PRINT_CHARGE', 'brand_new', 3]) {
        expect(WalletTransactionType.parse(raw), WalletTransactionType.other);
      }
    });

    test('pipeline enums fall back as before', () {
      for (final raw in [null, '', 'QUEUED', 'brand_new']) {
        expect(PipelineRunStatus.parse(raw), PipelineRunStatus.unknown);
        expect(PipelineJobStatus.parse(raw), PipelineJobStatus.unknown);
        expect(EligibilityIssueKind.parse(raw), EligibilityIssueKind.unknown);
        expect(PipelineTargetKind.parse(raw), PipelineTargetKind.fallback);
        expect(FanoutStrategy.parse(raw), FanoutStrategy.fallback);
      }
    });

    test('run status keeps no wire for unknown', () {
      expect(PipelineRunStatus.unknown.wire, isNull);
    });
  });
}
