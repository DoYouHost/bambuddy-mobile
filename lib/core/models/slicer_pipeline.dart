/// Slicer pipelines from `/slicer-pipelines` — a named bundle of the
/// printer / process / filament / bed-type picks a slice request needs.
///
/// The bundle and the *target* are two different things, and the server draws
/// that line in the schema: create takes the bundle, while `target_kind` /
/// `target_printer_id` / `target_model_class` / `fanout_strategy` are accepted
/// **on update alone** (`schemas/slicer_pipeline.py`). So a pipeline saved from
/// the slice form starts untargeted — hence [SlicerPipeline.isRunnable].
library;

import 'json_utils.dart';

/// A `{source, id}` preset reference — how a pipeline, and the slice request it
/// feeds, names a preset. No display name: it is resolved against the
/// `/slicer/presets` catalog at render time, since a pipeline can outlive the
/// preset it points at.
class PresetRef {
  const PresetRef({required this.source, required this.id});

  factory PresetRef.fromJson(Map<String, dynamic> json) => PresetRef(
        source: json['source'] as String? ?? 'standard',
        id: json['id']?.toString() ?? '',
      );

  /// One of `local`, `orca_cloud`, `cloud`, `standard` — same tiers as
  /// [SlicerPreset.source].
  final String source;
  final String id;

  Map<String, String> toJson() => {'source': source, 'id': id};

  @override
  bool operator ==(Object other) =>
      other is PresetRef && other.source == source && other.id == id;

  @override
  int get hashCode => Object.hash(source, id);
}

/// Which printers a pipeline run may dispatch to.
enum PipelineTargetKind {
  /// One pinned printer (`target_printer_id`).
  specificPrinter,

  /// Every printer of one model (`target_model_class`), with copies spread by
  /// the [FanoutStrategy].
  printerClass;

  /// The server's own default for a pipeline that has never been targeted
  /// (`SlicerPipelineResponse.target_kind`).
  static const fallback = PipelineTargetKind.printerClass;

  static PipelineTargetKind parse(String? raw) => switch (raw) {
        'specific_printer' => PipelineTargetKind.specificPrinter,
        'printer_class' => PipelineTargetKind.printerClass,
        _ => fallback,
      };

  String get wire => switch (this) {
        PipelineTargetKind.specificPrinter => 'specific_printer',
        PipelineTargetKind.printerClass => 'printer_class',
      };
}

/// How copies are spread over the printers of a targeted class. Ignored for
/// [PipelineTargetKind.specificPrinter], which has one printer by definition.
enum FanoutStrategy {
  maxParallel,
  fillOneFirst,
  roundRobin;

  static const fallback = FanoutStrategy.maxParallel;

  static FanoutStrategy parse(String? raw) => switch (raw) {
        'max_parallel' => FanoutStrategy.maxParallel,
        'fill_one_first' => FanoutStrategy.fillOneFirst,
        'round_robin' => FanoutStrategy.roundRobin,
        _ => fallback,
      };

  String get wire => switch (this) {
        FanoutStrategy.maxParallel => 'max_parallel',
        FanoutStrategy.fillOneFirst => 'fill_one_first',
        FanoutStrategy.roundRobin => 'round_robin',
      };
}

/// One saved pipeline (`SlicerPipelineResponse`).
class SlicerPipeline {
  const SlicerPipeline({
    required this.id,
    required this.name,
    required this.printerPreset,
    required this.processPreset,
    required this.filamentPresets,
    this.description,
    this.bedType,
    this.targetKind = PipelineTargetKind.fallback,
    this.targetPrinterId,
    this.targetModelClass,
    this.fanoutStrategy = FanoutStrategy.fallback,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  factory SlicerPipeline.fromJson(Map<String, dynamic> json) => SlicerPipeline(
        id: toIntOrNull(json['id']) ?? 0,
        name: json['name'] as String? ?? '',
        description: json['description'] as String?,
        printerPreset: _ref(json['printer_preset']),
        processPreset: _ref(json['process_preset']),
        filamentPresets: [
          for (final f in (json['filament_presets'] as List? ?? const []))
            if (f is Map<String, dynamic>) PresetRef.fromJson(f),
        ],
        bedType: json['bed_type'] as String?,
        targetKind: PipelineTargetKind.parse(json['target_kind'] as String?),
        targetPrinterId: toIntOrNull(json['target_printer_id']),
        targetModelClass: json['target_model_class'] as String?,
        fanoutStrategy:
            FanoutStrategy.parse(json['fanout_strategy'] as String?),
        createdBy: toIntOrNull(json['created_by']),
        createdAt: dateTimeFromJson(json['created_at']),
        updatedAt: dateTimeFromJson(json['updated_at']),
      );

  static PresetRef _ref(dynamic value) => value is Map<String, dynamic>
      ? PresetRef.fromJson(value)
      : const PresetRef(source: 'standard', id: '');

  final int id;
  final String name;
  final String? description;
  final PresetRef printerPreset;
  final PresetRef processPreset;

  /// One entry per AMS slot, **positional** — order matches the source plate's
  /// filament-slot order, exactly as `filament_presets` on a slice request.
  final List<PresetRef> filamentPresets;

  /// Null inherits the process preset's own plate.
  final String? bedType;

  final PipelineTargetKind targetKind;
  final int? targetPrinterId;

  /// A Bambu model code (`X1C`, `P1S`, …) when [targetKind] is
  /// [PipelineTargetKind.printerClass].
  final String? targetModelClass;
  final FanoutStrategy fanoutStrategy;

  final int? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Whether `POST /run` has somewhere to dispatch to. The run button reads
  /// this rather than reporting the server's `printer_not_set` /
  /// `class_not_set` back as a failure.
  bool get isRunnable => switch (targetKind) {
        PipelineTargetKind.specificPrinter => targetPrinterId != null,
        PipelineTargetKind.printerClass =>
          (targetModelClass ?? '').trim().isNotEmpty,
      };

  /// The create body (`SlicerPipelineCreate`) — without the four target fields,
  /// which that schema does not declare and Pydantic would drop silently.
  Map<String, dynamic> toCreateJson() => {
        'name': name,
        if (description != null) 'description': description,
        'printer_preset': printerPreset.toJson(),
        'process_preset': processPreset.toJson(),
        'filament_presets': [for (final f in filamentPresets) f.toJson()],
        if (bedType != null) 'bed_type': bedType,
      };
}
