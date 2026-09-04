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
import '../common/inline_note.dart';
import '../files/printer_download_job.dart';
import '../files/printer_selection_download.dart';

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
  PrinterSelectionDownload? _run;
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
      final run = PrinterSelectionDownload(repo, printerId: printerId);
      _run = run;
      cached = await run.run(
        files: [for (final file in files) (path: file.path, size: file.size)],
        fileName: fileName,
        scratchName: 'archive-media-${widget.archive.id}.download',
        onJob: _onJob,
        onProgress: _onProgress,
      );
      if (!mounted) return;
      // A bundle can be short of what was asked for: the server stages what it
      // could read rather than throwing the whole selection away, and a "saved"
      // that does not say so hands the user a ZIP they would have to count
      // themselves.
      final skipped = _job?.failed ?? 0;
      final saved = await _save(
        cached,
        fileName,
        l10n,
        extra: skipped > 0 ? l10n.pfmDownloadPartial(skipped) : null,
      );
      if (saved) {
        setState(_selected.clear);
        // Recorded only once the user actually has the bundle. A save dialog
        // backed out of produced nothing, and a warning about a download that
        // never landed reads, in a report, like a failure that happened.
        if (skipped > 0) _record('partial');
      }
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
  /// replaced — the same shape the web UI downloads under, and the same rule
  /// the timelapse export saves under ([safeFileStem]).
  String _bundleName() =>
      '${safeFileStem(widget.archive.displayName, fallback: 'archive')}'
      '-videos.zip';

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
                  _MediaRow(
                    id: 'archive_media.timelapse',
                    icon: Icons.movie_outlined,
                    title: _timelapseName(),
                    subtitle: _timelapseSubtitle(l10n),
                    onTap: widget.onTimelapse,
                  ),
                if (archive.hasPhotos)
                  _MediaRow(
                    id: 'archive_media.photos',
                    icon: Icons.photo_camera_outlined,
                    title: l10n.archivePhotosTitle,
                    subtitle: l10n.archiveMediaPhotoCount(archive.photos.length),
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
      else if (_error case final error?) ...[
        Text(error, style: t.body.copyWith(color: t.danger)),
        // A search over five FTP listings fails for reasons that pass — the
        // printer busy, the phone's Wi-Fi dropping. Without this the only way
        // to try again is to dismiss the sheet and find the button again.
        Align(
          alignment: Alignment.centerLeft,
          child: logTag(
            'archive_media.retry',
            TextButton(onPressed: _search, child: Text(l10n.retry)),
          ),
        ),
      ]
      else ...[
        if (files.isEmpty)
          Text(l10n.archiveMediaNothingOnPrinter, style: t.bodySoft),
        for (final file in files)
          _MediaRow(
            id: 'archive_media.file',
            icon: Icons.movie_outlined,
            title: file.name,
            subtitle: '${_kindOf(file, l10n)} · ${formatBytes(file.size)}',
            selected: _selected.contains(file.path),
            onTap: _busy ? null : () => _toggle(file.path),
          ),
        for (final warning in _media?.warnings ?? const <ArchiveMediaWarning>{})
          // Quiet ink and the plain info mark, not the warning triangle: none
          // of these stops the user getting what the sheet did find.
          InlineNote(
            _warningText(warning, l10n),
            icon: Icons.info_outline,
            padding: const EdgeInsets.only(top: 8),
          ),
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

  String _kindOf(ArchiveMediaFile file, AppLocalizations l10n) =>
      file.kind == ArchiveMediaKind.timelapse
          ? l10n.archiveMediaKindTimelapse
          : l10n.archiveMediaKindIpcam;

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

/// One row of the sheet: a name, what it is, and a leading mark that says which
/// of the two things this row does.
///
/// The card itself is the same either way — the sheet reads as one list — so
/// only the mark and the border carry the difference. **A row that opens** has
/// an icon for its kind and a chevron: it leaves the sheet for a viewer. **A
/// row that is picked** has a checkbox and, once ticked, the accent border: it
/// never leaves, it joins the download.
class _MediaRow extends StatelessWidget {
  const _MediaRow({
    required this.id,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.selected,
  });

  final String id;

  /// The leading mark. For a pickable row this is ignored — the checkbox says
  /// what the row is for, and a second icon beside it says nothing.
  final IconData icon;

  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  /// Null for a row that opens something; a tick state for one that is picked.
  final bool? selected;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final picked = selected ?? false;
    final row = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: picked ? t.accentGreen.withValues(alpha: 0.10) : t.subCard,
          border: Border.all(color: picked ? t.accentGreenInk : t.subCardBorder),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            // `accentGreenInk`, not `accentGreen`: the token doc draws the
            // line at text and icons on a pale surface, and the vivid swatch
            // reads 2.1:1 on the light card — under the 3:1 a control that
            // signals its own state has to clear.
            if (selected == null)
              Icon(icon, size: 20, color: t.accentGreenInk)
            else
              Icon(
                picked ? Icons.check_box : Icons.check_box_outline_blank,
                size: 20,
                color: picked ? t.accentGreenInk : t.textTertiary,
              ),
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
            if (selected == null)
              Icon(Icons.chevron_right, size: 20, color: t.textTertiary),
          ],
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: logTag(
        id,
        // The tick is the row's state, not a separate control: a screen reader
        // that read it alone would announce "ticked" with nothing to say what
        // was ticked. `checked` rather than `selected` because a checkbox is
        // what the row draws, and `MergeSemantics` so the name, the size and
        // the state arrive as one thing rather than three nodes to swipe
        // through.
        selected == null
            ? row
            : MergeSemantics(child: Semantics(checked: picked, child: row)),
      ),
    );
  }
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
            // `container: true` with it, or the phase text merges into the row
            // and the change is announced to nobody — the same pairing
            // [InlineNote] makes for its announcing note.
            container: true,
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
