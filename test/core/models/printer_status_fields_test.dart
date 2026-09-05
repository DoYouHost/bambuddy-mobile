import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Keeps `PrinterStatus`'s field lists in step.
///
/// The class writes its fields out four times — the constructor, `_fields`,
/// `mergedWith` and `_clearedIfOffline` — and three of those have to be
/// complete. Forgetting one is silent in every other way:
///
/// - missing from `mergedWith`, the field is dropped by every frame that does
///   not carry it, which for a status assembled from two lanes with disjoint
///   subsets means it blanks and reappears on a 5 s cycle;
/// - missing from `_fields`, a frame that changes only that field compares
///   equal to the one on screen and `ingestPoll` never publishes it, and two
///   statuses that differ hash alike.
///
/// None of that fails a test that does not already know to look, which is why
/// this one reads the source rather than the behaviour: the omission is a fact
/// about the code, and there is no single place all five lists pass through.
///
/// When this fails, add the field to whichever list the message names — do not
/// add it here.
void main() {
  /// Fields `_clearedIfOffline` deliberately drops: an unreachable printer has
  /// no live state, and the frame's telemetry is only the server's stale cache.
  /// The method's own doc argues each one; this test only refuses to let a name
  /// that is no longer a field sit in either place.
  late String source;
  late Set<String> fields;

  String bodyBetween(String start, String end) {
    final from = source.indexOf(start);
    expect(from, isNot(-1), reason: 'no "$start" in printer_status.dart');
    final to = source.indexOf(end, from + start.length);
    expect(to, isNot(-1), reason: 'no "$end" after "$start"');
    return source.substring(from, to);
  }

  setUpAll(() {
    source = File('lib/core/models/printer_status.dart').readAsStringSync();
    // The constructor is the definition of the list; everything else is a copy
    // of it. `required this.id` and `this.name` are the two spellings.
    final ctor = bodyBetween('const PrinterStatus({', '});');
    fields = RegExp(r'this\.(\w+)')
        .allMatches(ctor)
        .map((m) => m.group(1)!)
        .toSet();
    // A guard on the guard: a constructor that stopped being found would let
    // every assertion below pass over an empty set.
    expect(fields, contains('id'));
    expect(fields.length, greaterThan(20));
  });

  void expectComplete(String what, String body) {
    final missing = [
      for (final field in fields)
        if (!RegExp('\\b$field\\b').hasMatch(body)) field,
    ]..sort();
    expect(missing, isEmpty, reason: '$what does not mention $missing');
  }

  test('every field is compared and hashed', () {
    // `==` and `hashCode` both read this one list, so it is the only place the
    // omission can happen — and the only one this has to check.
    expectComplete('_fields', bodyBetween('List<Object?> get _fields => [', '];'));
  });

  test('every field is carried through mergedWith', () {
    // The one that costs a visible bug rather than a missed publish: a field
    // absent here is zeroed by the next frame that does not mention it.
    expectComplete(
      'mergedWith',
      bodyBetween('PrinterStatus mergedWith(', ')._clearedIfOffline();'),
    );
  });

  test('what survives going offline is still a field', () {
    // Deliberately a subset — the point of the method is that most of the
    // status does *not* survive. What it must not do is keep naming a field
    // that has since been renamed away, which reads as intent and is nothing.
    final kept = RegExp(r'(\w+):')
        .allMatches(bodyBetween('PrinterStatus _clearedIfOffline() {', '\n  }'))
        .map((m) => m.group(1)!)
        .toSet()
      ..remove('reason');

    expect(kept.difference(fields), isEmpty,
        reason: '_clearedIfOffline names something that is not a field');
    expect(kept, contains('ams'),
        reason: 'the physical AMS inventory survives a power-off');
  });
}
