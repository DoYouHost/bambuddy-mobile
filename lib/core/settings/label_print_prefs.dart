import '../models/spool_label.dart';

/// Where a rendered label file goes.
///
/// **The names are persisted values** (SharedPreferences); renaming one resets
/// that choice for every install.
enum LabelDestination {
  /// The platform print dialog (which also offers "Save as PDF").
  system,

  /// The share sheet.
  share,

  /// A "Save as…" dialog — how a PNG or ZIP is kept, for software that takes
  /// images.
  save,

  /// The LAN label print server.
  labelPrinter,
}

/// What the label sheet remembers between uses, so the second print does not
/// start from the defaults again. The web picker keeps the same things in the
/// browser.
class LabelPrintPrefs {
  const LabelPrintPrefs({
    this.monochrome = false,
    this.destination,
    this.format = SpoolLabelFormat.pdf,
    this.dpi = 300,
    this.fields = const {},
    this.copies = 1,
    this.cutAtEnd = true,
    this.cutEvery = 0,
  });

  final bool monochrome;

  /// Null until the user has chosen: the sheet then picks the label printer
  /// when one is set up and the system dialog otherwise.
  final LabelDestination? destination;

  final SpoolLabelFormat format;
  final int dpi;

  /// The chosen lines per template — a 40 × 30 label has room for less than a
  /// 75 × 55 one, so one set for all of them would not fit both. A template
  /// without an entry uses [SpoolLabelField.defaults].
  final Map<SpoolLabelTemplate, Set<SpoolLabelField>> fields;

  // The label print server's own job options (`/print`).
  final int copies;
  final bool cutAtEnd;
  final int cutEvery;

  /// Where the file goes, given what is possible right now: a PNG cannot be
  /// printed or sent to the print server (which takes PDF), and a label printer
  /// that has since been removed leaves nothing to send to.
  ///
  /// With no choice made yet the label printer is the default only when it is
  /// set up and [printerFits] the template — otherwise the first tap on
  /// "Print" would be a refusal. A choice made by hand is kept either way.
  LabelDestination resolveDestination({
    required bool printerSet,
    required bool printerFits,
    required bool png,
  }) {
    final chosen = destination;
    if (png) {
      return chosen == LabelDestination.save
          ? LabelDestination.save
          : LabelDestination.share;
    }
    if (chosen == null) {
      return printerSet && printerFits
          ? LabelDestination.labelPrinter
          : LabelDestination.system;
    }
    if (chosen == LabelDestination.labelPrinter && !printerSet) {
      return LabelDestination.system;
    }
    return chosen;
  }

  Set<SpoolLabelField> fieldsFor(SpoolLabelTemplate template) =>
      fields[template] ?? SpoolLabelField.defaults;

  LabelPrintPrefs copyWith({
    bool? monochrome,
    LabelDestination? destination,
    SpoolLabelFormat? format,
    int? dpi,
    Map<SpoolLabelTemplate, Set<SpoolLabelField>>? fields,
    int? copies,
    bool? cutAtEnd,
    int? cutEvery,
  }) => LabelPrintPrefs(
    monochrome: monochrome ?? this.monochrome,
    destination: destination ?? this.destination,
    format: format ?? this.format,
    dpi: dpi ?? this.dpi,
    fields: fields ?? this.fields,
    copies: copies ?? this.copies,
    cutAtEnd: cutAtEnd ?? this.cutAtEnd,
    cutEvery: cutEvery ?? this.cutEvery,
  );

  Map<String, dynamic> toJson() => {
    'monochrome': monochrome,
    if (destination != null) 'destination': destination!.name,
    'format': format.name,
    'dpi': dpi,
    'fields': {
      for (final e in fields.entries)
        e.key.wire: [for (final f in e.value) f.wire],
    },
    'copies': copies,
    'cut_at_end': cutAtEnd,
    'cut_every': cutEvery,
  };

  /// Tolerant: a value that is missing, of the wrong type or no longer a known
  /// name falls back to its default, so a stored blob from another version
  /// costs one setting, never the sheet.
  factory LabelPrintPrefs.fromJson(Map<String, dynamic> json) {
    int whole(String key, int fallback, {int min = 0, int? max}) {
      final v = json[key];
      if (v is! int || v < min || (max != null && v > max)) return fallback;
      return v;
    }

    final rawFields = json['fields'];
    final fields = <SpoolLabelTemplate, Set<SpoolLabelField>>{};
    if (rawFields is Map) {
      for (final template in SpoolLabelTemplate.values) {
        final list = rawFields[template.wire];
        if (list is! List) continue;
        fields[template] = {
          for (final wire in list) ?SpoolLabelField.fromWire(wire),
        };
      }
    }

    return LabelPrintPrefs(
      monochrome: json['monochrome'] == true,
      destination: LabelDestination.values
          .where((d) => d.name == json['destination'])
          .firstOrNull,
      format: SpoolLabelFormat.fromName(json['format']),
      dpi: spoolLabelDpiChoices.contains(json['dpi'])
          ? json['dpi'] as int
          : 300,
      fields: fields,
      copies: whole('copies', 1, min: 1, max: labelPrinterMaxCopies),
      cutAtEnd: json['cut_at_end'] != false,
      cutEvery: whole('cut_every', 0),
    );
  }
}

/// The print server's `MAX_COPIES`. `/info` reports it, but the stepper has to
/// exist before that answers.
const labelPrinterMaxCopies = 50;
