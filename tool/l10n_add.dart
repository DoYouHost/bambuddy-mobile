// Adds new strings to every lib/l10n/app_<lang>.arb from one JSON file
// (`just l10n-add <file>`):
//
//   {"wledTitle": {"en": "WLED", "pl": "WLED", "de": "WLED", "es": "WLED",
//                  "fr": "WLED", "@": {"placeholders": {}}}}
//
// Every language the directory holds is required; "@" is optional and goes to
// the template only, as the existing translations carry no metadata. Keys are
// appended as text, so nothing else in a file moves; `l10n_sync --apply` would
// rewrite each translation whole.
import 'dart:convert';
import 'dart:io';

const template = 'en';

/// [arb] with [entries] appended before its closing brace, the values of
/// [lang] only. Throws [FormatException] for a key [arb] already has.
String appendStrings(
  String arb,
  String lang,
  Map<String, Map<String, Object?>> entries,
) {
  final existing = jsonDecode(arb) as Map<String, dynamic>;
  final body = arb.trimRight();
  if (!body.endsWith('}')) throw const FormatException('not a JSON object');
  final lines = <String>[];
  for (final MapEntry(:key, :value) in entries.entries) {
    if (existing.containsKey(key)) {
      throw FormatException('$key is already in app_$lang.arb');
    }
    lines.add('  ${jsonEncode(key)}: ${jsonEncode(value[lang])}');
    final meta = value['@'];
    if (lang == template && meta != null) {
      final pretty = const JsonEncoder.withIndent('  ').convert(meta);
      lines.add('  ${jsonEncode('@$key')}: ${pretty.replaceAll('\n', '\n  ')}');
    }
  }
  final head = body.substring(0, body.length - 1).trimRight();
  return '$head,\n${lines.join(',\n')}\n}\n';
}

/// The entries of [json] checked against [languages]: a camelCase key, a
/// non-empty string for every language and nothing else but "@".
Map<String, Map<String, Object?>> parseEntries(
  String json,
  Set<String> languages,
) {
  final decoded = jsonDecode(json);
  if (decoded is! Map<String, dynamic> || decoded.isEmpty) {
    throw const FormatException('expected a non-empty JSON object');
  }
  final key = RegExp(r'^[a-z][A-Za-z0-9]*$');
  return {
    for (final MapEntry(key: name, :value) in decoded.entries)
      name: switch (value) {
        _ when !key.hasMatch(name) => throw FormatException(
          '$name is not a camelCase key',
        ),
        final Map<String, dynamic> byLang => _checked(name, byLang, languages),
        _ => throw FormatException('$name needs an object of languages'),
      },
  };
}

Map<String, Object?> _checked(
  String name,
  Map<String, dynamic> byLang,
  Set<String> languages,
) {
  final extra = byLang.keys.toSet().difference({...languages, '@'});
  if (extra.isNotEmpty) {
    throw FormatException('$name has languages this app lacks: $extra');
  }
  for (final lang in languages) {
    if (byLang[lang] case final String text when text.isNotEmpty) continue;
    throw FormatException('$name has no "$lang" string');
  }
  if (byLang['@'] case final Object meta when meta is! Map) {
    throw FormatException('$name: "@" must be an object');
  }
  return byLang;
}

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: dart run tool/l10n_add.dart <strings.json>');
    exit(64);
  }
  final files = {
    for (final f in Directory('lib/l10n').listSync().whereType<File>())
      if (RegExp(r'app_(\w+)\.arb$').firstMatch(f.path) case final m?)
        m.group(1)!: f,
  };
  try {
    final entries = parseEntries(
      File(args.single).readAsStringSync(),
      files.keys.toSet(),
    );
    // Every file is worked out before any is written, so a clash in one
    // leaves all of them as they were.
    final updated = {
      for (final MapEntry(key: lang, value: file) in files.entries)
        file: appendStrings(file.readAsStringSync(), lang, entries),
    };
    updated.forEach((file, text) => file.writeAsStringSync(text));
    stdout.writeln(
      'added ${entries.length} key(s) to ${files.length} .arb files',
    );
  } on FormatException catch (e) {
    stderr.writeln('l10n-add: ${e.message}');
    exit(65);
  }
}
