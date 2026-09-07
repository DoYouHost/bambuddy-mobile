import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Keeps the `action_failed` tag worth having.
///
/// The record is read next to the tap that caused it: `ui tap files.folder.delete`
/// followed by `app action_failed action=files.folder.delete`. That only works
/// while the two vocabularies are the same one. A tag that names no control
/// still *looks* fine in a review — it just quietly costs the correlation, and
/// the reader is back to asking the reporter which button they pressed, which
/// is the failure this log exists to prevent. `printer.clear_plate` against a
/// control called `printer.plate_clear` is exactly that, and is what prompted
/// this test.
///
/// Source-scanning rather than runtime, because the mismatch is a fact about
/// the code and there is no single place both vocabularies pass through.
void main() {
  /// Actions that deliberately name no control, with the reason. A step inside
  /// a flow can fail before or between the controls that drive it, and naming
  /// the nearest button would be a lie about what the user touched.
  const flowSteps = <String, String>{
    'queue.pick_printer':
        'fetching the candidates, before the picker sheet exists',
    'queue.plate_clear':
        'the scheduler gate inside the start flow, not a button of its own',
    'project.link_folder': 'the section action, which carries no id of its own',
    'project.attachment_upload': 'likewise',
    'pipeline_run.check':
        'the eligibility pre-flight, which runs itself between the pipeline '
        'pick and the start button rather than from a control',
    'spool_form.save_model_presets':
        'the second write the Save button makes, after the spool itself — '
        'a step in that flow, not a control of its own',
  };

  /// Every way a control declares its id, including the material variant and
  /// the postfix form.
  final tagForms = [
    RegExp(r"logTag\(\s*'([^']+)'"),
    RegExp(r"logTagMaterial\(\s*'([^']+)'"),
    RegExp(r"\.tagged\('([^']+)'\)"),
    RegExp(r"\.taggedMaterial\('([^']+)'"),
    // `confirmDialog(id:)` names its two buttons `<id>.confirm` / `<id>.cancel`.
    RegExp(r"id:\s*'([^']+)'"),
  ];

  /// The literal tags handed to the funnel. Interpolated ones (`plug.${…}`)
  /// are composed at runtime and cannot be checked from source, and neither can
  /// the ones a helper takes positionally — `action:` and `logId:` are what a
  /// scan can see, which is most of them.
  final actionForms = [
    RegExp(r"action:\s*'([^'$]+)'"),
    // A bare `logId:` is a namespace a tag is composed from (`_TagList` builds
    // `<logId>.new`); a dotted one is already the whole id.
    RegExp(r"logId:\s*'([^'$]*\.[^'$]*)'"),
  ];

  late Set<String> actions;
  late Set<String> controls;

  setUpAll(() {
    actions = {};
    controls = {};
    for (final file
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      final source = file.readAsStringSync();
      for (final form in tagForms) {
        controls.addAll(form.allMatches(source).map((m) => m.group(1)!));
      }
      for (final form in actionForms) {
        actions.addAll(form.allMatches(source).map((m) => m.group(1)!));
      }
    }
    // `_TagSheetActions.createTag` composes its tag from the sheet it is on, so
    // neither vocabulary carries the whole string in source.
    controls.addAll(
      [
        'tag_filter',
        'file_tags',
        'bulk_tags',
        'tag_manage',
      ].map((s) => '$s.new'),
    );
  });

  test('the sweep found both vocabularies', () {
    // A regex that stopped matching would make every assertion below vacuous.
    expect(actions, hasLength(greaterThan(20)));
    expect(controls, hasLength(greaterThan(100)));
  });

  test('every action tag names a control the user can actually touch', () {
    final orphans = actions
        .difference(controls)
        .difference(flowSteps.keys.toSet());

    expect(
      orphans,
      isEmpty,
      reason:
          'These tags correlate with no control, so a report cannot say '
          'which button was pressed. Either fix the tag to match the id on the '
          'control, add the id to the control, or list it in `flowSteps` with '
          'the reason it has none.',
    );
  });

  test('the flow-step exemptions are all still in use', () {
    // An exemption left behind after its call site changed would silently
    // re-open the hole it was granted for.
    for (final entry in flowSteps.entries) {
      expect(actions, contains(entry.key), reason: 'stale exemption');
    }
  });

  test('a tag carries no data and is not a sentence', () {
    // `docs/diagnostics-log.md`: ids are dotted, lowercase, stable, never
    // localized, and carry no data — `archive.card`, not `archive.card.MyModel`.
    final grammar = RegExp(r'^[a-z0-9_]+(\.[a-z0-9_]+)*$');
    for (final tag in actions) {
      expect(grammar.hasMatch(tag), isTrue, reason: '"$tag" is not an id');
    }
  });
}
