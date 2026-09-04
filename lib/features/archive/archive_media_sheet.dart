import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/diagnostics/diagnostic_recorder.dart';
import '../../core/diagnostics/log_event.dart';
import '../../core/diagnostics/log_tag.dart';
import '../../core/models/archive.dart';
import '../../core/models/archive_media.dart';
import '../../core/models/printer_download_job.dart';
import '../../core/theme/dash_text.dart';
import '../../core/theme/dash_theme.dart';
import '../../data/printer_files_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import '../../providers.dart';
import '../common/api_failure_snack.dart';
import '../common/dash_progress.dart';
import '../common/dash_sheet.dart';
import '../common/dash_snack.dart';
import '../common/device_files.dart';
import '../common/file_export.dart';
import '../common/format_bytes.dart';
import '../files/printer_download_job.dart';

/// Whether this server can be asked what a print left on its printer.
///
/// Only the printer half of the sheet rests on this — the timelapse and the
/// photos are the archive's own, and every server generation serves them.
final archiveMediaSupportedProvider = FutureProvider<bool>(
  (ref) => ref.watch(archiveRepositoryProvider).supportsPrinterMedia(),
);

/// Whether a print has anything for the sheet to show at all.
///
/// [printerSearchable] is [archiveMediaSupportedProvider]: without it a print
/// whose only media is still on the printer has nothing to show, and the entry
/// point stays away rather than opening onto an empty sheet.
bool archiveHasMedia(Archive archive, {required bool printerSearchable}) =>
    archive.hasTimelapse ||
    archive.hasPhotos ||
    (printerSearchable && archive.printerId != null);

/// Opens the media sheet for [archive]. [onTimelapse] and [onPhotos] hand the
/// viewers back to the screen that owns the navigation.
Future<void> openArchiveMediaSheet(
  BuildContext context,
  Archive archive, {
  required VoidCallback onTimelapse,
  required VoidCallback onPhotos,
}) =>
    dashSheet<void>(
      context,
      builder: (_) => _ArchiveMediaSheet(
        archive: archive,
        onTimelapse: onTimelapse,
        onPhotos: onPhotos,
      ),
    );

/// Everything a finished print has to look at or to keep, grouped by where it
/// actually is — because what can be done with it follows from that.
///
/// **On the server** is what bambuddy already holds: the attached timelapse and
/// the photos. Both open in their own viewer, which is where playing, saving to
/// the gallery and sharing live.
///
/// **On the printer** is what is still only on its storage — a timelapse nobody
/// claimed, and the `/ipcam` chunks that fall inside the print. Those are ticked
/// and pulled down through the same prepared download the file manager uses, so
/// a selection of several hundred-megabyte clips reports its progress and can be
/// called off.
class _ArchiveMediaSheet extends ConsumerStatefulWidget {
  const _ArchiveMediaSheet({
    required this.archive,
    required this.onTimelapse,
    required this.onPhotos,
  });

  final Archive archive;
  final VoidCallback onTimelapse;
  final VoidCallback onPhotos;

  @override
  ConsumerState<_ArchiveMediaSheet> createState() => _ArchiveMediaSheetState();
}

class _ArchiveMediaSheetState extends ConsumerState<_ArchiveMediaSheet> {
  /// Whether the printer can be asked at all. False leaves that section out
  /// entirely rather than showing an empty one under a header.
  bool _searchable = false;

  ArchivePrinterMedia? _media;
  bool _loading = true;

  /// Localized failure of the search itself, which is not the same as a search
  /// that found nothing.
  String? _error;

  /// Printer paths that are ticked. The path is the identity: two `/ipcam`
  /// chunks can share a name across directories.
  final Set<String> _selected = {};

  bool _busy = false;
  double? _progress;
  PrinterDownloadJob? _job;
  PrinterDownloadRun? _run;
  bool _cancelRequested = false;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    // Same courtesy as the file manager: a sheet the user dismissed mid-
    // preparation leaves the server pulling files off the printer for a bundle
    // nobody will save. Errors are dropped — there is nobody left to tell.
    _run?.cancel().ignore();
    super.dispose();
  }

  Future<void> _search() async {
    // The same gate the entry point watches, so the button and the section it
    // opens cannot disagree about whether this server can be asked.
    final searchable = widget.archive.printerId != null &&
        await ref.read(archiveMediaSupportedProvider.future);
    if (!mounted) return;
    if (!searchable) {
      setState(() {
        _searchable = false;
        _loading = false;
      });
      return;
    }
    setState(() {
      _searchable = true;
      _loading = true;
      _error = null;
    });
    try {
      final media =
          await ref.read(archiveRepositoryProvider).printerMedia(widget.archive.id);
      if (!mounted) return;
      setState(() {
        // Null is a server without the route, which the check above was meant
        // to have ruled out — so it reads as "found nothing" rather than as an
        // error the user could act on.
        _media = media ?? const ArchivePrinterMedia();
        _loading = false;
        final files = _media!.remoteFiles;
        // One candidate is the ordinary case for a print whose timelapse was
        // never attached: ticking it saves a tap that has no alternative.
        if (files.length == 1) _selected.add(files.first.path);
      });
    } on AppApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.localized(AppLocalizations.of(context));
      });
    }
  }

  /// Pulls the ticked printer files down and asks where to keep them.
  Future<void> _downloadSelected() async {
    final printerId = _media?.printerId ?? widget.archive.printerId;
    if (_busy || printerId == null || _selected.isEmpty) return;
    final l10n = AppLocalizations.of(context);
    final repo = ref.read(printerFilesRepositoryProvider);
    final files =
        _media!.remoteFiles.where((f) => _selected.contains(f.path)).toList();
    final paths = files.map((f) => f.path).toList();
    final single = paths.length == 1;
    // A remote entry always has a path — the model drops one that has not — so
    // its last segment is a better fallback name than a made-up one.
    final fileName = single
        ? _nameOr(files.first.name, paths.first.split('/').last)
        : _bundleName();
    setState(() {
      _busy = true;
      _progress = null;
      _job = null;
      _cancelRequested = false;
    });
    File? cached;
    try {
      cached = await downloadToCacheFile(
        scratchName: 'archive-media-${widget.archive.id}.download',
        download: (savePath) async {
          if (!await _downloadAsJob(
              repo, printerId, files, fileName, savePath, single)) {
            // No preparation route on this server: the same bytes, fetched the
            // way every server generation serves them — one held request, no
            // progress and no way to call it off.
            if (single) {
              await repo.downloadFileTo(
                printerId,
                paths.first,
                savePath,
                onProgress: _onProgress,
              );
            } else {
              await repo.downloadZipTo(
                printerId,
                paths,
                savePath,
                onProgress: _onProgress,
              );
            }
          }
          return null;
        },
        name: (_) => fileName,
      );
      if (!mounted) return;
      // A bundle can be short of what was asked for: the server stages what it
      // could read rather than throwing the whole selection away, and a "saved"
      // that does not say so hands the user a ZIP they would have to count
      // themselves.
      final skipped = _job?.failed ?? 0;
      if (skipped > 0) _record('partial');
      final saved = await _save(
        cached,
        fileName,
        l10n,
        extra: skipped > 0 ? l10n.pfmDownloadPartial(skipped) : null,
      );
      if (saved) setState(_selected.clear);
    } on PrinterDownloadFailure catch (e) {
      _record(e.reason.name);
      if (mounted) _snack(_prepareFailureText(e, l10n));
    } on AppApiException catch (e) {
      showApiFailure(
        mounted ? ScaffoldMessenger.of(context) : null,
        e,
        l10n,
        action: 'archive_media.download',
        message: _downloadFailure(e, l10n),
      );
    } finally {
      if (cached != null) await discardCacheCopy(cached);
      _run = null;
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  /// Runs the selection through the server's preparation job, when this server
  /// has one. False means it has not and the caller falls back to the legacy
  /// route, which every server still serves.
  Future<bool> _downloadAsJob(
    PrinterFilesRepository repo,
    int printerId,
    List<ArchiveMediaFile> files,
    String fileName,
    String savePath,
    bool single,
  ) async {
    if (!await repo.supportsDownloadJobs()) return false;
    final run = PrinterDownloadRun(repo, printerId: printerId);
    _run = run;
    return run.download(
      paths: files.map((f) => f.path).toList(),
      sizes: _sizesFor(files),
      filename: fileName,
      // One file is asked for natively: the user gets the video rather than a
      // ZIP holding one video. The server accepts that for exactly one path.
      asZip: !single,
      savePath: savePath,
      onJob: _onJob,
      onProgress: _onProgress,
    );
  }

  /// Sizes for the selection, all or nothing.
  ///
  /// The server spends them on an up-front free-space check and its schema
  /// demands one per path; an entry the FTP listing could not size arrives as
  /// `0`, and a check run on invented numbers is worse than no check.
  Map<String, int> _sizesFor(List<ArchiveMediaFile> files) {
    final sizes = <String, int>{};
    for (final file in files) {
      if (file.size <= 0) return const {};
      sizes[file.path] = file.size;
    }
    return sizes;
  }

  /// Hands [file] to the system save dialog and reports what came of it. True
  /// means the user has the file.
  ///
  /// [extra] is appended to the confirmation rather than snacked after it: two
  /// bars in a row queue, so the second — the one that says files were left out
  /// — would arrive four seconds after the sheet had moved on.
  Future<bool> _save(
    File file,
    String fileName,
    AppLocalizations l10n, {
    String? extra,
  }) async {
    final saved = await saveDownloadedFile(
      file,
      fileName: fileName,
      mimeType: mimeTypeForFileName(fileName),
    );
    if (!mounted) return false;
    switch (saved.outcome) {
      case DeviceFileOutcome.cancelled:
        return false;
      case DeviceFileOutcome.failed:
        _snack(l10n.pfmDownloadNotSaved);
        return false;
      case DeviceFileOutcome.done:
        _snack(extra == null
            ? l10n.archiveMediaSaved
            : '${l10n.archiveMediaSaved} · $extra');
        return true;
    }
  }

  /// [name] when the server sent one, [fallback] otherwise.
  String _nameOr(String? name, String fallback) =>
      (name == null || name.isEmpty) ? fallback : name;

  /// `<print name>-videos.zip`, with anything a filesystem could choke on
  /// replaced — the same shape the web UI downloads under.
  String _bundleName() {
    final safe =
        widget.archive.displayName.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');
    return '${safe.isEmpty ? 'archive' : safe}-videos.zip';
  }

  /// Dio reports progress per received chunk, which on a gigabyte of video is
  /// thousands of callbacks. Only a change the bar can show is worth a frame; a
  /// server streaming without a length reports -1 and the bar stays
  /// indeterminate rather than inventing a fraction.
  void _onProgress(int received, int total) {
    if (!mounted) return;
    final next = total > 0 ? (received / total * 100).floor() / 100 : null;
    if (next == _progress) return;
    setState(() => _progress = next);
  }

  void _onJob(PrinterDownloadJob job) {
    if (!mounted) return;
    setState(() {
      _job = job;
      // The bar belongs to whichever phase is running: file counts while the
      // server pulls files off the printer, bytes once the transfer starts.
      if (job.state != PrinterDownloadJobState.ready) _progress = job.progress;
    });
  }

  Future<void> _cancelPreparation() async {
    final run = _run;
    if (run == null) return;
    // Reported straight away: the DELETE and the poll it interrupts both take a
    // moment, and a Cancel button that stays lit reads as one that did nothing.
    setState(() => _cancelRequested = true);
    await run.cancel();
  }

  bool get _preparing =>
      _busy && _job != null && _job!.state != PrinterDownloadJobState.ready;

  void _snack(String message) {
    if (mounted) ScaffoldMessenger.of(context).snack(message);
  }

  /// Records how a prepared download ended, for a report that says the button
  /// was pressed and then nothing arrived. The server's own message is
  /// deliberately not recorded: it can name the file it stopped on, and a file
  /// name is the user's own text (`docs/diagnostics-log.md`).
  void _record(String state) {
    DiagnosticRecorder.active?.add(
      LogSource.app,
      'archive_media_download',
      lvl: LogLevel.warn,
      fields: {
        'archive': widget.archive.id,
        'state': state,
        'requested': _job?.requested,
        'staged': _job?.successful,
        'skipped': _job?.failed,
      },
    );
  }

  String _prepareFailureText(
    PrinterDownloadFailure failure,
    AppLocalizations l10n,
  ) =>
      switch (failure.reason) {
        PrinterDownloadStopped.cancelled => l10n.pfmDownloadCancelled,
        // The server's own sentence names the limit or the file it stopped on,
        // which is worth more than the generic line.
        PrinterDownloadStopped.failed =>
          failure.detail ?? l10n.pfmDownloadPrepareFailed,
        PrinterDownloadStopped.lost => l10n.pfmDownloadPrepareFailed,
      };

  /// The three refusals the download routes explain in a way the user can act
  /// on. Null for everything else, which keeps the shared wording — and null on
  /// older servers too, which answer none of these.
  String? _downloadFailure(AppApiException e, AppLocalizations l10n) =>
      switch (e.statusCode) {
        413 => l10n.pfmDownloadTooLarge,
        504 => l10n.pfmDownloadTookTooLong,
        507 => l10n.pfmDownloadNoServerSpace,
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final theme = Theme.of(context);
    final archive = widget.archive;
    return logTag(
      'sheet.archive_media',
      SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.archiveMediaAction, style: theme.textTheme.titleMedium),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  archive.displayName,
                  style: t.bodySoft,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (archive.hasTimelapse || archive.hasPhotos) ...[
                _SectionHeader(title: l10n.archiveMediaOnServer),
                if (archive.hasTimelapse)
                  _OpenRow(
                    id: 'archive_media.timelapse',
                    icon: Icons.movie_outlined,
                    title: _timelapseName(),
                    subtitle: _timelapseSubtitle(l10n),
                    onTap: widget.onTimelapse,
                  ),
                if (archive.hasPhotos)
                  _OpenRow(
                    id: 'archive_media.photos',
                    icon: Icons.photo_camera_outlined,
                    title: l10n.archivePhotosTitle,
                    subtitle: '${archive.photos.length}',
                    onTap: widget.onPhotos,
                  ),
              ],
              if (_searchable) ..._printerSection(l10n, t),
            ],
          ),
        ),
      ),
    );
  }

  /// The half that is still only on the printer. Absent altogether on a server
  /// that cannot be asked, rather than an empty list under a header.
  List<Widget> _printerSection(AppLocalizations l10n, DashTokens t) {
    final files = _media?.remoteFiles ?? const <ArchiveMediaFile>[];
    return [
      _SectionHeader(
        title: l10n.archiveMediaOnPrinter(files.length),
        trailing: files.isEmpty
            ? null
            : logTag(
                'archive_media.select_all',
                TextButton(
                  onPressed: _busy ? null : _toggleAll,
                  child: Text(_selected.length == files.length
                      ? l10n.pfmDeselectAll
                      : l10n.pfmSelectAll),
                ),
              ),
      ),
      if (_loading)
        _Searching(label: l10n.archiveMediaSearching, t: t)
      else if (_error case final error?)
        Text(error, style: t.body.copyWith(color: t.danger))
      else ...[
        if (files.isEmpty)
          Text(l10n.archiveMediaNothingOnPrinter, style: t.bodySoft),
        for (final file in files)
          _RemoteRow(
            file: file,
            selected: _selected.contains(file.path),
            onTap: _busy ? null : () => _toggle(file.path),
          ),
        for (final warning in _media?.warnings ?? const <ArchiveMediaWarning>{})
          _Warning(text: _warningText(warning, l10n), t: t),
        if (files.isNotEmpty) ...[
          const SizedBox(height: 12),
          _DownloadBar(
            busy: _busy,
            preparing: _preparing,
            progress: _progress,
            label: _barLabel(l10n),
            cancelEnabled: !_cancelRequested,
            onCancel: _cancelPreparation,
            onDownload: _selected.isEmpty ? null : _downloadSelected,
          ),
        ],
      ],
    ];
  }

  /// The attached video's own name. Known from the archive before the search
  /// answers; the search only confirms it and adds the size.
  String _timelapseName() => _nameOr(
        _media?.localTimelapse?.name,
        (widget.archive.timelapsePath ?? '').split('/').last,
      );

  /// `Timelapse · 42 MB`, with the size only once the server has stated one.
  String _timelapseSubtitle(AppLocalizations l10n) {
    final size = _media?.localTimelapse?.size ?? 0;
    return size > 0
        ? '${l10n.archiveMediaKindTimelapse} · ${formatBytes(size)}'
        : l10n.archiveMediaKindTimelapse;
  }

  void _toggle(String path) => setState(() {
        if (!_selected.remove(path)) _selected.add(path);
      });

  void _toggleAll() => setState(() {
        final all = _media?.remoteFiles.map((f) => f.path) ?? const <String>[];
        if (_selected.length == all.length) {
          _selected.clear();
        } else {
          _selected
            ..clear()
            ..addAll(all);
        }
      });

  /// What the bar says: the phase while something is running, the count of what
  /// is ticked otherwise. The file count rides along with the phase rather than
  /// sitting in its own column — the sheet is narrower than the file manager's
  /// action bar, which is where that second column came from.
  String _barLabel(AppLocalizations l10n) {
    if (!_busy) return l10n.archiveMediaDownloadSelected(_selected.length);
    final job = _job;
    if (_preparing && job != null && job.requested > 1) {
      return '${l10n.pfmPreparingOnServer} '
          '${job.successful + job.failed}/${job.requested}';
    }
    return _preparing ? l10n.pfmPreparingOnServer : l10n.pfmDownloading;
  }

  String _warningText(ArchiveMediaWarning warning, AppLocalizations l10n) =>
      switch (warning) {
        ArchiveMediaWarning.printerFilesForbidden =>
          l10n.archiveMediaNoFilePermission,
        ArchiveMediaWarning.printerMissing => l10n.archiveMediaPrinterMissing,
        ArchiveMediaWarning.timelapseUnavailable =>
          l10n.archiveMediaTimelapseUnavailable,
        ArchiveMediaWarning.ipcamUnavailable =>
          l10n.archiveMediaIpcamUnavailable,
      };
}

/// Which of the two places the rows under it live in. The whole point of the
/// sheet is that the answer differs, so it is said once per group rather than
/// repeated in every row.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Padding(
      // The trailing button brings its own height, so the gap under the header
      // is only needed on the plain one.
      padding: EdgeInsets.only(top: 16, bottom: trailing == null ? 6 : 0),
      child: Row(
        children: [
          Expanded(child: Text(title, style: t.label)),
          ?trailing,
        ],
      ),
    );
  }
}

class _Searching extends StatelessWidget {
  const _Searching({required this.label, required this.t});

  final String label;
  final DashTokens t;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          const DashSpinner(size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: t.bodySoft)),
        ],
      );
}

/// A row that opens something rather than selecting it. The chevron is the
/// distinction from the ticked rows below, which never leave the sheet.
class _OpenRow extends StatelessWidget {
  const _OpenRow({
    required this.id,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String id;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: logTag(
        id,
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: t.subCard,
              border: Border.all(color: t.subCardBorder),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: t.accentGreen),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: t.body,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(subtitle, style: t.bodySoft),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: 20, color: t.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RemoteRow extends StatelessWidget {
  const _RemoteRow({
    required this.file,
    required this.selected,
    required this.onTap,
  });

  final ArchiveMediaFile file;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final kind = file.kind == ArchiveMediaKind.timelapse
        ? l10n.archiveMediaKindTimelapse
        : l10n.archiveMediaKindIpcam;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: logTag(
        'archive_media.file',
        // The tick is the row's state, not a separate control: a screen reader
        // that read the checkbox alone would announce "selected" with nothing
        // to say what was selected.
        Semantics(
          selected: selected,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: selected
                    ? t.accentGreen.withValues(alpha: 0.10)
                    : t.subCard,
                border: Border.all(
                  color: selected ? t.accentGreen : t.subCardBorder,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    selected ? Icons.check_box : Icons.check_box_outline_blank,
                    size: 20,
                    color: selected ? t.accentGreen : t.textTertiary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          file.name,
                          style: t.body,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '$kind · ${formatBytes(file.size)}',
                          style: t.bodySoft,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Why part of the search came back empty. Quiet ink, not amber: none of these
/// stops the user getting what the sheet did find.
class _Warning extends StatelessWidget {
  const _Warning({required this.text, required this.t});

  final String text;
  final DashTokens t;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 16, color: t.textTertiary),
            const SizedBox(width: 6),
            Expanded(child: Text(text, style: t.labelSoft)),
          ],
        ),
      );
}

class _DownloadBar extends StatelessWidget {
  const _DownloadBar({
    required this.busy,
    required this.preparing,
    required this.progress,
    required this.label,
    required this.cancelEnabled,
    required this.onCancel,
    required this.onDownload,
  });

  final bool busy;
  final bool preparing;
  final double? progress;
  final String label;
  final bool cancelEnabled;
  final VoidCallback onCancel;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    if (!busy) {
      return SizedBox(
        width: double.infinity,
        child: logTag(
          'archive_media.download',
          FilledButton.icon(
            onPressed: onDownload,
            icon: const Icon(Icons.download),
            label: Text(label),
          ),
        ),
      );
    }
    return Row(
      children: [
        DashSpinner(size: 20, value: progress),
        const SizedBox(width: 10),
        Expanded(
          // A live region so a screen reader says the phase changed: the row is
          // the only place that distinguishes waiting for the server from
          // waiting for the transfer, and a change of text alone is announced
          // to nobody.
          child: Semantics(
            liveRegion: true,
            child: Text(
              label,
              style: t.bodySoft,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        // Only while the server is still pulling files. Once the transfer
        // starts there is nothing worth stopping: the bytes come off the
        // server's own disk and the token is already spent.
        //
        // Disabled rather than removed once pressed — a control that vanishes
        // under the finger takes screen-reader focus with it.
        if (preparing)
          logTag(
            'archive_media.download_cancel',
            IconButton(
              onPressed: cancelEnabled ? onCancel : null,
              tooltip: l10n.cancel,
              icon: const Icon(Icons.close),
              color: t.textSecondary,
            ),
          ),
      ],
    );
  }
}
