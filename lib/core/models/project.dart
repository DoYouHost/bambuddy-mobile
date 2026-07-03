import 'package:json_annotation/json_annotation.dart';

import 'json_utils.dart';

part 'project.g.dart';

/// Print project from `GET /projects/` (list view — `ProjectListResponse`).
/// Groups prints (archives + queue) toward a goal with progress + counts.
/// Defensive parsing: numeric fields via tolerant helpers, unknown keys ignored.
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class ProjectListResponse {
  const ProjectListResponse({
    required this.id,
    required this.name,
    this.description,
    this.color,
    this.status = 'active',
    this.targetCount,
    this.targetPartsCount,
    this.budget,
    this.createdAt,
    this.archiveCount = 0,
    this.totalItems = 0,
    this.completedCount = 0,
    this.failedCount = 0,
    this.queueCount = 0,
    this.progressPercent,
    this.url,
    this.coverImageFilename,
    this.archives = const [],
  });

  factory ProjectListResponse.fromJson(Map<String, dynamic> json) =>
      _$ProjectListResponseFromJson(json);

  final int id;
  final String name;
  final String? description;
  final String? color;
  final String status;

  @JsonKey(fromJson: toIntOrNull)
  final int? targetCount;
  @JsonKey(fromJson: toIntOrNull)
  final int? targetPartsCount;
  @JsonKey(fromJson: toDoubleOrNull)
  final double? budget;

  final String? createdAt;

  @JsonKey(fromJson: toInt)
  final int archiveCount;
  @JsonKey(fromJson: toInt)
  final int totalItems;
  @JsonKey(fromJson: toInt)
  final int completedCount;
  @JsonKey(fromJson: toInt)
  final int failedCount;
  @JsonKey(fromJson: toInt)
  final int queueCount;

  @JsonKey(fromJson: toDoubleOrNull)
  final double? progressPercent;

  final String? url;
  final String? coverImageFilename;

  @JsonKey(fromJson: _archivesFromJson)
  final List<ArchivePreview> archives;

  bool get hasCover => coverImageFilename != null && coverImageFilename!.isNotEmpty;
}

/// Lightweight archive thumbnail entry embedded in project list/detail.
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class ArchivePreview {
  const ArchivePreview({
    required this.id,
    this.printName,
    this.thumbnailPath,
    this.status,
    this.filamentType,
    this.filamentColor,
  });

  factory ArchivePreview.fromJson(Map<String, dynamic> json) =>
      _$ArchivePreviewFromJson(json);

  final int id;
  final String? printName;
  final String? thumbnailPath;
  final String? status;
  final String? filamentType;
  final String? filamentColor;

  bool get hasThumbnail => thumbnailPath != null && thumbnailPath!.isNotEmpty;
}

/// Child project preview shown as a chip in the parent's detail.
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class ProjectChildPreview {
  const ProjectChildPreview({
    required this.id,
    required this.name,
    this.color,
    this.status = 'active',
    this.progressPercent,
  });

  factory ProjectChildPreview.fromJson(Map<String, dynamic> json) =>
      _$ProjectChildPreviewFromJson(json);

  final int id;
  final String name;
  final String? color;
  final String status;

  @JsonKey(fromJson: toDoubleOrNull)
  final double? progressPercent;
}

/// Aggregate project statistics (`ProjectStats`) — all numeric, tolerant parsing.
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class ProjectStats {
  const ProjectStats({
    this.totalArchives = 0,
    this.totalItems = 0,
    this.completedPrints = 0,
    this.failedPrints = 0,
    this.queuedPrints = 0,
    this.inProgressPrints = 0,
    this.totalPrintTimeHours = 0,
    this.totalFilamentGrams = 0,
    this.progressPercent,
    this.partsProgressPercent,
    this.estimatedCost = 0,
    this.totalEnergyKwh = 0,
    this.totalEnergyCost = 0,
    this.remainingPrints,
    this.remainingParts,
    this.bomTotalItems = 0,
    this.bomCompletedItems = 0,
    this.bomCost = 0,
  });

  factory ProjectStats.fromJson(Map<String, dynamic> json) =>
      _$ProjectStatsFromJson(json);

  @JsonKey(fromJson: toInt)
  final int totalArchives;
  @JsonKey(fromJson: toInt)
  final int totalItems;
  @JsonKey(fromJson: toInt)
  final int completedPrints;
  @JsonKey(fromJson: toInt)
  final int failedPrints;
  @JsonKey(fromJson: toInt)
  final int queuedPrints;
  @JsonKey(fromJson: toInt)
  final int inProgressPrints;
  @JsonKey(fromJson: toDouble)
  final double totalPrintTimeHours;
  @JsonKey(fromJson: toDouble)
  final double totalFilamentGrams;
  @JsonKey(fromJson: toDoubleOrNull)
  final double? progressPercent;
  @JsonKey(fromJson: toDoubleOrNull)
  final double? partsProgressPercent;
  @JsonKey(fromJson: toDouble)
  final double estimatedCost;
  @JsonKey(fromJson: toDouble)
  final double totalEnergyKwh;
  @JsonKey(fromJson: toDouble)
  final double totalEnergyCost;
  @JsonKey(fromJson: toIntOrNull)
  final int? remainingPrints;
  @JsonKey(fromJson: toIntOrNull)
  final int? remainingParts;
  @JsonKey(fromJson: toInt)
  final int bomTotalItems;
  @JsonKey(fromJson: toInt)
  final int bomCompletedItems;
  @JsonKey(fromJson: toDouble)
  final double bomCost;
}

/// Full project detail (`ProjectResponse`) from `GET /projects/{id}`.
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class ProjectResponse {
  const ProjectResponse({
    required this.id,
    required this.name,
    this.description,
    this.color,
    this.status = 'active',
    this.targetCount,
    this.targetPartsCount,
    this.notes,
    this.attachments = const [],
    this.tags,
    this.dueDate,
    this.priority = 'normal',
    this.budget,
    this.isTemplate = false,
    this.templateSourceId,
    this.parentId,
    this.parentName,
    this.children = const [],
    this.createdAt,
    this.updatedAt,
    this.stats,
    this.url,
    this.coverImageFilename,
  });

  factory ProjectResponse.fromJson(Map<String, dynamic> json) =>
      _$ProjectResponseFromJson(json);

  final int id;
  final String name;
  final String? description;
  final String? color;
  final String status;

  @JsonKey(fromJson: toIntOrNull)
  final int? targetCount;
  @JsonKey(fromJson: toIntOrNull)
  final int? targetPartsCount;

  final String? notes;

  /// Attachment filenames — server returns either plain strings or objects;
  /// parsed tolerantly to filenames (see [_attachmentsFromJson]).
  @JsonKey(fromJson: _attachmentsFromJson)
  final List<String> attachments;

  /// Comma-separated tag string (NOT a list per API).
  final String? tags;

  final String? dueDate;
  final String priority;

  @JsonKey(fromJson: toDoubleOrNull)
  final double? budget;

  @JsonKey(defaultValue: false)
  final bool isTemplate;
  final int? templateSourceId;
  final int? parentId;
  final String? parentName;

  @JsonKey(fromJson: _childrenFromJson)
  final List<ProjectChildPreview> children;

  final String? createdAt;
  final String? updatedAt;
  final ProjectStats? stats;
  final String? url;
  final String? coverImageFilename;

  bool get hasCover => coverImageFilename != null && coverImageFilename!.isNotEmpty;

  DateTime? get dueDateParsed =>
      dueDate == null ? null : DateTime.tryParse(dueDate!);

  /// Tags split into trimmed non-empty parts (UI renders as chips).
  List<String> get tagList => (tags ?? '')
      .split(',')
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty)
      .toList();
}

/// BOM (bill of materials) line item (`BOMItemResponse`).
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class BomItem {
  const BomItem({
    required this.id,
    required this.projectId,
    required this.name,
    this.quantityNeeded = 1,
    this.quantityAcquired = 0,
    this.unitPrice,
    this.sourcingUrl,
    this.archiveId,
    this.archiveName,
    this.stlFilename,
    this.remarks,
    this.sortOrder = 0,
    this.isComplete = false,
  });

  factory BomItem.fromJson(Map<String, dynamic> json) =>
      _$BomItemFromJson(json);

  final int id;
  final int projectId;
  final String name;

  @JsonKey(fromJson: toInt)
  final int quantityNeeded;
  @JsonKey(fromJson: toInt)
  final int quantityAcquired;
  @JsonKey(fromJson: toDoubleOrNull)
  final double? unitPrice;
  final String? sourcingUrl;
  final int? archiveId;
  final String? archiveName;
  final String? stlFilename;
  final String? remarks;
  @JsonKey(fromJson: toInt)
  final int sortOrder;
  @JsonKey(defaultValue: false)
  final bool isComplete;
}

/// Project timeline event (`TimelineEvent`).
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class TimelineEvent {
  const TimelineEvent({
    this.eventType = '',
    this.timestamp,
    this.title = '',
    this.description,
    this.metadata,
  });

  factory TimelineEvent.fromJson(Map<String, dynamic> json) =>
      _$TimelineEventFromJson(json);

  final String eventType;
  final String? timestamp;
  final String title;
  final String? description;
  final Map<String, dynamic>? metadata;

  DateTime? get timestampParsed =>
      timestamp == null ? null : DateTime.tryParse(timestamp!);
}

// --- Request bodies (write to server; hand-built maps, null fields omitted) ---

/// Body for `POST /projects/` (`ProjectCreate`).
class ProjectCreate {
  const ProjectCreate({
    required this.name,
    this.description,
    this.color,
    this.targetCount,
    this.targetPartsCount,
    this.notes,
    this.tags,
    this.dueDate,
    this.priority = 'normal',
    this.budget,
    this.parentId,
    this.url,
  });

  final String name;
  final String? description;
  final String? color;
  final int? targetCount;
  final int? targetPartsCount;
  final String? notes;
  final String? tags;
  final String? dueDate;
  final String priority;
  final double? budget;
  final int? parentId;
  final String? url;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'name': name,
        'description': ?description,
        'color': ?color,
        'target_count': ?targetCount,
        'target_parts_count': ?targetPartsCount,
        'notes': ?notes,
        'tags': ?tags,
        'due_date': ?dueDate,
        'priority': priority,
        'budget': ?budget,
        'parent_id': ?parentId,
        'url': ?url,
      };
}

/// Body for `PATCH /projects/{id}` (`ProjectUpdate`) — all fields optional;
/// only non-null entries are sent so untouched fields keep server values.
class ProjectUpdate {
  const ProjectUpdate({
    this.name,
    this.description,
    this.color,
    this.status,
    this.targetCount,
    this.targetPartsCount,
    this.notes,
    this.tags,
    this.dueDate,
    this.priority,
    this.budget,
    this.parentId,
    this.url,
  });

  final String? name;
  final String? description;
  final String? color;
  final String? status;
  final int? targetCount;
  final int? targetPartsCount;
  final String? notes;
  final String? tags;
  final String? dueDate;
  final String? priority;
  final double? budget;
  final int? parentId;
  final String? url;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'name': ?name,
        'description': ?description,
        'color': ?color,
        'status': ?status,
        'target_count': ?targetCount,
        'target_parts_count': ?targetPartsCount,
        'notes': ?notes,
        'tags': ?tags,
        'due_date': ?dueDate,
        'priority': ?priority,
        'budget': ?budget,
        'parent_id': ?parentId,
        'url': ?url,
      };
}

/// Body for `POST /projects/{id}/bom` (`BOMItemCreate`) and reused for PATCH.
///
/// There is no settable `is_complete` field — completion is derived server-side
/// from `quantity_acquired >= quantity_needed`. To toggle "done", set
/// [quantityAcquired] to [quantityNeeded] (complete) or `0` (incomplete).
class BomItemInput {
  const BomItemInput({
    required this.name,
    this.quantityNeeded,
    this.quantityAcquired,
    this.unitPrice,
    this.clearUnitPrice = false,
    this.sourcingUrl,
    this.clearSourcingUrl = false,
    this.archiveId,
    this.stlFilename,
    this.remarks,
    this.clearRemarks = false,
  });

  final String name;
  final int? quantityNeeded;
  final int? quantityAcquired;
  final double? unitPrice;
  final String? sourcingUrl;
  final int? archiveId;
  final String? stlFilename;
  final String? remarks;

  /// The backend's `update_bom_item` only clears `unit_price`/`sourcing_url`/
  /// `remarks` on a "falsy but present" value (`0` / `""`) — a `null` or an
  /// omitted key both read as "leave unchanged" server-side. So a cleared
  /// text field can't be expressed via `unitPrice == null` (that already means
  /// "untouched"); these flags request the explicit falsy sentinel instead.
  final bool clearUnitPrice;
  final bool clearSourcingUrl;
  final bool clearRemarks;

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'name': name,
      'quantity_needed': ?quantityNeeded,
      'quantity_acquired': ?quantityAcquired,
      'archive_id': ?archiveId,
      'stl_filename': ?stlFilename,
    };
    if (clearUnitPrice) {
      map['unit_price'] = 0;
    } else if (unitPrice != null) {
      map['unit_price'] = unitPrice;
    }
    if (clearSourcingUrl) {
      map['sourcing_url'] = '';
    } else if (sourcingUrl != null) {
      map['sourcing_url'] = sourcingUrl;
    }
    if (clearRemarks) {
      map['remarks'] = '';
    } else if (remarks != null) {
      map['remarks'] = remarks;
    }
    return map;
  }
}

/// Attachments come either as bare filename strings or objects carrying a
/// `filename`/`name`/`path` field. Normalize to a list of filenames.
List<String> _attachmentsFromJson(dynamic value) {
  if (value is! List) return const [];
  final out = <String>[];
  for (final item in value) {
    if (item is String) {
      out.add(item);
    } else if (item is Map) {
      final name = item['filename'] ?? item['name'] ?? item['path'];
      if (name is String && name.isNotEmpty) out.add(name);
    }
  }
  return out;
}

List<ArchivePreview> _archivesFromJson(dynamic value) =>
    parseJsonList(value, ArchivePreview.fromJson);

List<ProjectChildPreview> _childrenFromJson(dynamic value) =>
    parseJsonList(value, ProjectChildPreview.fromJson);
