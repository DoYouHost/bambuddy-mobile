/// Slice job from `GET /slice-jobs/{id}` — the background job spawned by a
/// `POST .../slice`. The client enqueues, then polls this until terminal.
///
/// Defensive parsing: the server leaves `progress`/`result`/error fields null
/// depending on the phase, and shapes evolve, so everything past id/status is
/// optional.
class SliceJob {
  const SliceJob({
    required this.jobId,
    required this.status,
    this.sourceName,
    this.progress,
    this.result,
    this.errorStatus,
    this.errorDetail,
  });

  factory SliceJob.fromJson(Map<String, dynamic> json) {
    final prog = json['progress'];
    final res = json['result'];
    return SliceJob(
      jobId: (json['job_id'] as num?)?.toInt() ?? -1,
      status: json['status'] as String? ?? 'pending',
      sourceName: json['source_name'] as String?,
      progress: prog is Map<String, dynamic> ? SliceProgress.fromJson(prog) : null,
      result: res is Map<String, dynamic> ? SliceResult.fromJson(res) : null,
      errorStatus: (json['error_status'] as num?)?.toInt(),
      errorDetail: json['error_detail'] as String?,
    );
  }

  /// `pending` / `running` / `completed` / `failed`.
  final int jobId;
  final String status;
  final String? sourceName;
  final SliceProgress? progress;
  final SliceResult? result;
  final int? errorStatus;
  final String? errorDetail;

  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';
  bool get isTerminal => isCompleted || isFailed;
}

/// Live slicer progress (`stage`, `total_percent`) surfaced while running.
class SliceProgress {
  const SliceProgress({this.stage, this.totalPercent});

  factory SliceProgress.fromJson(Map<String, dynamic> json) => SliceProgress(
        stage: json['stage'] as String?,
        totalPercent: (json['total_percent'] as num?)?.toInt(),
      );

  final String? stage;
  final int? totalPercent;

  /// Fraction 0..1 for a progress bar, or null when unknown (indeterminate).
  double? get fraction => totalPercent == null ? null : totalPercent! / 100.0;
}

/// Result of a completed slice — a new library file plus its estimates.
class SliceResult {
  const SliceResult({
    this.libraryFileId,
    this.name,
    this.printTimeSeconds,
    this.filamentUsedG,
  });

  factory SliceResult.fromJson(Map<String, dynamic> json) => SliceResult(
        libraryFileId: (json['library_file_id'] as num?)?.toInt(),
        name: json['name'] as String?,
        printTimeSeconds: (json['print_time_seconds'] as num?)?.toInt(),
        filamentUsedG: (json['filament_used_g'] as num?)?.toDouble(),
      );

  final int? libraryFileId;
  final String? name;
  final int? printTimeSeconds;
  final double? filamentUsedG;
}
