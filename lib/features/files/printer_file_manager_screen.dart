import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diagnostics/diagnostic_recorder.dart';
import '../../core/diagnostics/log_event.dart';
import '../../core/diagnostics/log_tag.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/format/datetime_format.dart';
import '../../core/models/printer_download_job.dart';
import '../../core/models/printer_file.dart';
import '../../core/theme/dash_text.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import '../../providers.dart';
import '../common/api_failure_snack.dart';
import '../common/confirm_dialog.dart';
import '../common/dash_progress.dart';
import '../common/dash_search_field.dart';
import '../common/dash_snack.dart';
import '../common/format_bytes.dart';
import '../common/sliver_search_bar.dart';
import '../common/device_files.dart';
import '../common/file_export.dart';
import 'printer_download_job.dart';
import 'printer_selection_download.dart';

/// Client-side sort keys for the printer file list (the endpoint doesn't sort).
enum PrinterFileSort { nameAsc, nameDesc, sizeAsc, sizeDesc, dateAsc, dateDesc }

/// Browse a printer's on-device storage: navigate folders, filter/sort, then
/// download or delete files. Shown only for online printers (offline FTP fails).
///
/// State is local (not a Riverpod notifier): a listing is a live FTP snapshot
/// scoped to this screen, refreshed on navigation / pull / after a mutation.
class PrinterFileManagerScreen extends ConsumerStatefulWidget {
  const PrinterFileManagerScreen({
    super.key,
    required this.printerId,
    required this.printerName,
  });

  final int printerId;
  final String printerName;

  @override
  ConsumerState<PrinterFileManagerScreen> createState() =>
      _PrinterFileManagerScreenState();
}

class _PrinterFileManagerScreenState
    extends ConsumerState<PrinterFileManagerScreen> {
  String _path = '/';
  List<PrinterFile>? _files; // null = not loaded yet
  bool _loading = false;
  String? _error; // localized load error
  // The listing came back empty because the printer did not answer, which older
  // servers cannot tell us — then this stays false and an empty listing reads as
  // an empty folder, exactly as before.
  bool _printerUnavailable = false;
  PrinterStorage _storage = const PrinterStorage();

  PrinterFileSort _sort = PrinterFileSort.nameAsc;
  String _query = '';
  final Set<String> _selected = {}; // full paths of selected files
  bool _busy = false; // download/delete in progress
  // Fraction of the running download, or null while the server has not said how
  // much there is to come.
  double? _downloadProgress;
  // The server-side preparation, while one is running: what it last reported,
  // and the handle Cancel needs. Both null on the legacy path, which has
  // neither a phase to report nor a way to be called off.
  PrinterDownloadJob? _job;
  PrinterSelectionDownload? _run;
  // Cancel has been asked for but the poll it interrupts has not come round
  // yet. Kept apart from [_job] because that one is the record's evidence:
  // clearing it to take the button away lost the counts the log is for.
  bool _cancelRequested = false;

  // Quick-navigation shortcuts, mirroring the server web UI.
  static const _quickDirs = [
    ('/', _QuickTab.root),
    ('/cache', _QuickTab.cache),
    ('/model', _QuickTab.models),
    ('/timelapse', _QuickTab.timelapse),
  ];

  @override
  void initState() {
    super.initState();
    _load();
    _loadStorage();
  }

  @override
  void dispose() {
    // Leaving the screen abandons the download, so the server is told to stop
    // rather than left pulling gigabytes off the printer for a bundle nothing
    // will save: `_download`'s `mounted` guards skip the save dialog and its
    // `finally` discards the cache copy, but neither reaches the server.
    // Errors are dropped — the request is a courtesy and there is nobody left
    // to tell.
    _run?.cancel().ignore();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _printerUnavailable = false;
      _selected.clear();
    });
    try {
      final repo = ref.read(printerFilesRepositoryProvider);
      final listing = await repo.listFiles(widget.printerId, _path);
      if (!mounted) return;
      setState(() {
        _files = listing.files;
        _printerUnavailable = listing.printerUnavailable;
        _loading = false;
      });
    } on AppApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.localized(AppLocalizations.of(context));
      });
    }
  }

  Future<void> _loadStorage() async {
    final storage =
        await ref.read(printerFilesRepositoryProvider).fetchStorage(widget.printerId);
    if (!mounted) return;
    setState(() => _storage = storage);
  }

  void _navigateTo(String path) {
    if (path == _path) {
      _load();
      return;
    }
    setState(() {
      _path = path;
      _query = '';
      _files = null;
    });
    _load();
  }

  void _navigateUp() {
    if (_path == '/') return;
    final parts = _path.split('/').where((p) => p.isNotEmpty).toList()..removeLast();
    _navigateTo(parts.isEmpty ? '/' : '/${parts.join('/')}');
  }

  /// Files after search filter, folders first, then the selected sort applied
  /// within each group (matches the server web UI ordering).
  List<PrinterFile> get _visible {
    final files = _files ?? const <PrinterFile>[];
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? [...files]
        : files.where((f) => f.name.toLowerCase().contains(q)).toList();
    filtered.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return switch (_sort) {
        PrinterFileSort.nameAsc =>
          a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        PrinterFileSort.nameDesc =>
          b.name.toLowerCase().compareTo(a.name.toLowerCase()),
        PrinterFileSort.sizeAsc => a.size.compareTo(b.size),
        PrinterFileSort.sizeDesc => b.size.compareTo(a.size),
        PrinterFileSort.dateAsc => _compareDate(a, b),
        PrinterFileSort.dateDesc => _compareDate(b, a),
      };
    });
    return filtered;
  }

  int _compareDate(PrinterFile a, PrinterFile b) {
    final da = a.modifiedAt, db = b.modifiedAt;
    if (da == null && db == null) return 0;
    if (da == null) return 1; // unknown dates sort last
    if (db == null) return -1;
    return da.compareTo(db);
  }

  List<PrinterFile> get _selectableFiles =>
      _visible.where((f) => !f.isDirectory).toList();

  void _toggleSelection(String path) => setState(() {
        _selected.contains(path) ? _selected.remove(path) : _selected.add(path);
      });

  void _toggleSelectAll() {
    final all = _selectableFiles.map((f) => f.path).toSet();
    setState(() {
      if (_selected.containsAll(all) && all.isNotEmpty) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(all);
      }
    });
  }

  /// Pulls the selection down and asks the user where to keep it.
  ///
  /// Streamed into a cache file rather than read into memory: a printer's card
  /// holds gigabytes, the server will now bundle as much of it as is asked for,
  /// and the bytes used to pass through the phone's RAM on their way to the save
  /// dialog. The dialog stays — [saveDownloadedFile] copies the finished file
  /// into the chosen location on the platform side, so the size never reaches
  /// Dart.
  Future<void> _download() async {
    if (_selected.isEmpty || _busy) return;
    final l10n = AppLocalizations.of(context);
    final repo = ref.read(printerFilesRepositoryProvider);
    final paths = _selected.toList();
    setState(() {
      _busy = true;
      _downloadProgress = null;
      _job = null;
      _cancelRequested = false;
    });
    // Dropped in the `finally`, whichever way this leaves — including the two
    // `mounted` returns, which are how a copy used to be left behind on a screen
    // the user walked away from. Declared out here so that block can see it.
    File? cached;
    try {
      final single = paths.length == 1;
      final fileName = single
          ? paths.first.split('/').last
          : '${safeFileStem(widget.printerName, fallback: 'printer')}-files.zip';
      final run = PrinterSelectionDownload(repo, printerId: widget.printerId);
      _run = run;
      cached = await run.run(
        files: _itemsFor(paths),
        fileName: fileName,
        scratchName: 'printer-files-${widget.printerId}.download',
        onJob: _onDownloadJob,
        onProgress: _onDownloadProgress,
      );
      if (!mounted) return;
      final saved = await saveDownloadedFile(
        cached,
        fileName: fileName,
        mimeType: mimeTypeForFileName(fileName),
      );
      if (!mounted) return;
      switch (saved.outcome) {
        case DeviceFileOutcome.cancelled:
          return;
        case DeviceFileOutcome.failed:
          _snack(l10n.pfmDownloadNotSaved);
        case DeviceFileOutcome.done:
          setState(_selected.clear);
          // A bundle can be short of what was asked for: the server stages what
          // it could read and reports the rest rather than throwing the whole
          // selection away, and a "saved" that does not say so hands the user a
          // ZIP they would have to count themselves.
          final skipped = _job?.failed ?? 0;
          if (skipped > 0) _recordPreparedDownload('partial');
          _snack(skipped > 0
              ? '${l10n.pfmDownloadSaved} · ${l10n.pfmDownloadPartial(skipped)}'
              : l10n.pfmDownloadSaved);
      }
    } on PrinterDownloadFailure catch (e) {
      _recordPreparedDownload(e.reason.name);
      if (mounted) _snack(_prepareFailureText(e, l10n));
    } on AppApiException catch (e) {
      showApiFailure(
        mounted ? ScaffoldMessenger.of(context) : null,
        e,
        l10n,
        action: 'printer_files.download',
        message: _downloadFailure(e, l10n),
      );
    } finally {
      // The save dialog copies the file on the platform side and returns only
      // once it has, so by here nothing is reading this copy — not the user's
      // saved file, and never the printer's own, which a download does not
      // touch. Keeping it would leave a duplicate of every distinct file name
      // in the cache until Android runs short of storage. The share sheet is
      // the case where this would be wrong (see `file_export.dart`), and it is
      // not the hand-off this screen uses.
      if (cached != null) await discardCacheCopy(cached);
      _run = null;
      if (mounted) {
        // [_job] deliberately survives: the record above is written from it,
        // and the next download clears it. Nothing reads it once [_busy] is
        // false — the row is back to the selection count.
        setState(() {
          _busy = false;
          _downloadProgress = null;
        });
      }
    }
  }

  /// Dio reports progress per received chunk, which on a gigabyte of models is
  /// thousands of callbacks — each one rebuilding the whole listing for a bar
  /// that moves by a fraction of a pixel. Only a change the bar can show is
  /// worth a frame. A server streaming without a length reports -1 as the total,
  /// and then the bar stays indeterminate rather than inventing a fraction.
  void _onDownloadProgress(int received, int total) {
    if (!mounted) return;
    final next = total > 0 ? (received / total * 100).floor() / 100 : null;
    if (next == _downloadProgress) return;
    setState(() => _downloadProgress = next);
  }

  /// The selection as the download wants it: a path and the size the listing
  /// gave it.
  ///
  /// A size the FTP listing could not read arrives as `0` and is passed on as
  /// one — `PrinterFilesRepository` is what decides whether a set of numbers is
  /// worth telling the server, and inventing a figure here to make the set look
  /// complete is exactly what that rule exists to stop.
  List<PrinterDownloadItem> _itemsFor(List<String> paths) {
    final byPath = {
      for (final f in _files ?? const <PrinterFile>[]) f.path: f.size,
    };
    return [
      for (final path in paths) (path: path, size: byPath[path] ?? 0),
    ];
  }

  /// Every state the preparation reports, for the phase label and the bar.
  void _onDownloadJob(PrinterDownloadJob job) {
    if (!mounted) return;
    setState(() {
      _job = job;
      // The bar belongs to whichever phase is running: file counts while the
      // server pulls files off the printer, bytes once the transfer starts.
      // Left alone on a `ready` job so the switch happens on the first byte
      // rather than as a jump back to nothing.
      if (job.state != PrinterDownloadJobState.ready) {
        _downloadProgress = job.progress;
      }
    });
  }

  /// Calls off a running preparation. The run itself then ends by throwing
  /// [PrinterDownloadStopped.cancelled], which is where the snack comes from —
  /// so this only has to ask.
  Future<void> _cancelPreparation() async {
    final run = _run;
    if (run == null) return;
    // Reported straight away: the DELETE and the poll it interrupts both take a
    // moment, and a Cancel button that stays lit reads as one that did nothing.
    setState(() => _cancelRequested = true);
    await run.cancel();
  }

  /// Records how a prepared download ended, for a report that says the button
  /// was pressed and then nothing arrived.
  ///
  /// The counts are what tell the three cases apart afterwards: a preparation
  /// that never started, one the user called off part-way, and a bundle the
  /// server had to leave files out of.
  ///
  /// **The server's own message is deliberately not recorded.** It is worth
  /// showing on screen, but it can name the file it stopped on, and a file name
  /// is the user's own text — the one thing this log refuses to carry
  /// (`docs/diagnostics-log.md`).
  void _recordPreparedDownload(String state) {
    final job = _job;
    DiagnosticRecorder.active?.add(
      LogSource.app,
      'printer_download',
      lvl: LogLevel.warn,
      fields: {
        'printer': widget.printerId,
        'state': state,
        'requested': job?.requested,
        'staged': job?.successful,
        'skipped': job?.failed,
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
        // which is worth more than the generic line — see
        // [PrinterDownloadFailure.detail] on why it is not localized.
        PrinterDownloadStopped.failed =>
          failure.detail ?? l10n.pfmDownloadPrepareFailed,
        PrinterDownloadStopped.lost => l10n.pfmDownloadPrepareFailed,
      };

  /// The three refusals the download routes explain in a way the user can act
  /// on: the bundle exceeds what the server will build, the server has no disk
  /// space to build it in, or it ran past its own preparation ceiling. Null for
  /// everything else, which keeps the shared wording — and null on older
  /// servers too, which answer none of these.
  String? _downloadFailure(AppApiException e, AppLocalizations l10n) =>
      switch (e.statusCode) {
        413 => l10n.pfmDownloadTooLarge,
        504 => l10n.pfmDownloadTookTooLong,
        507 => l10n.pfmDownloadNoServerSpace,
        _ => null,
      };

  Future<void> _delete() async {
    if (_selected.isEmpty || _busy) return;
    final l10n = AppLocalizations.of(context);
    final paths = _selected.toList();
    final confirmed = await confirmDialog(
      context,
      title: l10n.pfmDeleteConfirmTitle,
      message: l10n.pfmDeleteConfirmBody(paths.length),
      confirmLabel: l10n.pfmDelete,
      destructive: true,
      id: 'printer_files_delete',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    final repo = ref.read(printerFilesRepositoryProvider);
    var deleted = 0;
    final failures = <AppApiException>[];
    for (final path in paths) {
      try {
        await repo.deleteFile(widget.printerId, path);
        deleted++;
      } on AppApiException catch (e) {
        failures.add(e);
      }
    }
    // Each refusal is its own call and worth its own record, but only the last
    // one's wording becomes the snack — and none of it is delivered if the
    // screen went away while the batch ran. Recording them all as told would
    // say a dozen people were stopped where one message appeared, or none.
    final delivered = mounted;
    for (var i = 0; i < failures.length; i++) {
      recordActionFailure(
        failures[i],
        action: 'printer_files.delete',
        shown: delivered && i == failures.length - 1,
      );
    }
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(failures.isEmpty
        ? l10n.pfmDeleted(deleted)
        : failures.last.localized(l10n));
    await _load();
    await _loadStorage();
  }

  void _snack(String message) => ScaffoldMessenger.of(context).snack(message, replaceCurrent: true);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final selectable = _selectableFiles;
    final allSelected =
        selectable.isNotEmpty && _selected.containsAll(selectable.map((f) => f.path));

    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: dashAppBar(
          context,
          title: l10n.pfmTitle,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(18),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                widget.printerName,
                style: t.label,
              ),
            ),
          ),
          actions: [
            if (_storage.usedBytes != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    l10n.pfmStorageUsed(formatBytes(_storage.usedBytes!)),
                    style: t.monoLabel,
                  ),
                ),
              ),
            logTag(
              'printer_files.sort',
              PopupMenuButton<PrinterFileSort>(
                icon: Icon(Icons.sort, color: t.textSecondary),
                tooltip: l10n.pfmSortTooltip,
                initialValue: _sort,
                onSelected: (s) => setState(() => _sort = s),
                itemBuilder: (_) => [
                  _sortItem(PrinterFileSort.nameAsc, l10n.pfmSortNameAsc),
                  _sortItem(PrinterFileSort.nameDesc, l10n.pfmSortNameDesc),
                  _sortItem(PrinterFileSort.sizeDesc, l10n.pfmSortSizeLargest),
                  _sortItem(PrinterFileSort.sizeAsc, l10n.pfmSortSizeSmallest),
                  _sortItem(PrinterFileSort.dateDesc, l10n.pfmSortDateNewest),
                  _sortItem(PrinterFileSort.dateAsc, l10n.pfmSortDateOldest),
                ],
              ),
            ),
            logTag(
              'printer_files.refresh',
              IconButton(
                icon: Icon(Icons.refresh, color: t.textSecondary),
                tooltip: l10n.pfmRefreshTooltip,
                onPressed: _loading ? null : _load,
              ),
            ),
          ],
        ),
        // Quick-nav + breadcrumb stay pinned (navigation); only the search row
        // rolls away with the scrollable list below it.
        body: Column(
          children: [
            _quickNav(t, l10n),
            _breadcrumb(t, l10n),
            Expanded(
              child: _content(l10n, t, selectable.isNotEmpty, allSelected),
            ),
          ],
        ),
        bottomNavigationBar:
            _selected.isEmpty ? null : _actionBar(l10n, t),
      ),
    );
  }

  // Tag on the child: a wrapped `PopupMenuItem` is no longer a `PopupMenuEntry`.
  PopupMenuItem<PrinterFileSort> _sortItem(PrinterFileSort s, String label) =>
      PopupMenuItem(
        value: s,
        child: logTag('printer_files.sort_option', Text(label)),
      );

  Widget _quickNav(DashTokens t, AppLocalizations l10n) => SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          children: [
            for (final (path, tab) in _quickDirs)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(_quickLabel(tab, l10n)),
                  selected: _path == path,
                  onSelected: (_) => _navigateTo(path),
                  showCheckmark: false,
                  backgroundColor: t.subCard,
                  side: BorderSide(color: t.subCardBorder),
                  selectedColor: t.accentGreen.withValues(alpha: 0.18),
                  labelStyle: t.label.copyWith(color: _path == path ? t.accentGreenInk : t.textSecondary),
                ).tagged('printer_files.quick_dir'),
              ),
          ],
        ),
      );

  String _quickLabel(_QuickTab tab, AppLocalizations l10n) => switch (tab) {
        _QuickTab.root => l10n.pfmTabRoot,
        _QuickTab.cache => l10n.pfmTabCache,
        _QuickTab.models => l10n.pfmTabModels,
        _QuickTab.timelapse => l10n.pfmTabTimelapse,
      };

  Widget _breadcrumb(DashTokens t, AppLocalizations l10n) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.hairline)),
        ),
        child: Row(
          children: [
            logTag(
              'printer_files.up',
              IconButton(
                icon: Icon(Icons.arrow_back, color: t.textSecondary),
                // Named, because an icon alone reads as "unlabelled button" —
                // and named for what it does here: it climbs a directory, it
                // does not go back through the app.
                tooltip: l10n.pfmUp,
                // Default density on purpose. `VisualDensity.compact` took the
                // tap target under the 48x48 dp a control has to offer, on the
                // one button in this bar.
                onPressed: _path == '/' ? null : _navigateUp,
              ),
            ),
            Expanded(
              child: Text(
                _path,
                overflow: TextOverflow.ellipsis,
                style: t.monoValue,
              ),
            ),
          ],
        ),
      );

  // Outer padding is supplied by the enclosing [DashSliverSearchBar].
  Widget _searchAndSelectAll(
    DashTokens t,
    AppLocalizations l10n,
    bool hasSelectable,
    bool allSelected,
  ) =>
      Row(
        children: [
          Expanded(
            child: DashSearchField(
              id: 'printer_files.search',
              hintText: l10n.pfmSearchHint,
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          if (hasSelectable)
            logTag(
              'printer_files.select_all',
              TextButton(
                onPressed: _toggleSelectAll,
                style: TextButton.styleFrom(foregroundColor: t.accentGreenInk),
                child: Text(
                  allSelected ? l10n.pfmDeselectAll : l10n.pfmSelectAll,
                ),
              ),
            ),
        ],
      );

  Widget _content(
    AppLocalizations l10n,
    DashTokens t,
    bool hasSelectable,
    bool allSelected,
  ) {
    if (_loading && _files == null) {
      return const DashLoading();
    }
    if (_error != null) {
      return _centered(
        icon: Icons.error_outline,
        message: _error!,
        tokens: t,
        action: FilledButton(
          style: dashPrimaryButtonStyle(t),
          onPressed: _load,
          child: Text(l10n.retry),
        ).tagged('printer_files.retry'),
      );
    }
    final items = _visible;
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          DashSliverSearchBar(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: _searchAndSelectAll(t, l10n, hasSelectable, allSelected),
          ),
          if (items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _printerUnavailable
                  ? _centered(
                      icon: Icons.cloud_off,
                      message: l10n.pfmPrinterUnavailable,
                      tokens: t,
                      action: FilledButton(
                        style: dashPrimaryButtonStyle(t),
                        onPressed: _load,
                        child: Text(l10n.retry),
                      ).tagged('printer_files.retry'),
                    )
                  : _centered(
                      icon: Icons.folder_open,
                      message: (_files?.isEmpty ?? true)
                          ? l10n.pfmEmpty
                          : l10n.pfmNoMatches,
                      tokens: t,
                    ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              sliver: SliverList.separated(
                itemCount: items.length,
                separatorBuilder: (_, _) => Divider(
                    height: 1, indent: 16, endIndent: 16, color: t.hairline),
                itemBuilder: (_, i) => _row(items[i], t),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(PrinterFile file, DashTokens t) {
    if (file.isDirectory) {
      return logTag(
        'printer_files.folder',
        ListTile(
          leading: Icon(Icons.folder, color: t.accentGreenInk),
          title: Text(
            file.name,
            overflow: TextOverflow.ellipsis,
            style: t.titleSm,
          ),
          trailing: Icon(Icons.chevron_right, color: t.textTertiary),
          onTap: () => _navigateTo(file.path),
        )
      );
    }
    final selected = _selected.contains(file.path);
    return logTag(
      'printer_files.file',
      // The tick is the row's state, not a control of its own. Left to itself
      // the Checkbox is a second interactive node with no name — a screen
      // reader offers "tick box, not ticked" with nothing to say which file it
      // belongs to, and the file name arrives separately after it. Excluded and
      // restated on the row, the whole thing reads as one item, and the tap
      // target is the row it always was.
      MergeSemantics(
        child: Semantics(
          checked: selected,
          child: ListTile(
            leading: ExcludeSemantics(
              child: Checkbox(
                value: selected,
                onChanged: (_) => _toggleSelection(file.path),
                activeColor: t.accentGreen,
                checkColor: const Color(0xFF0A0C08),
              ),
            ),
            title: Text(
              file.name,
              overflow: TextOverflow.ellipsis,
              style: t.titleSm,
            ),
            subtitle: Text(
              _subtitle(file),
              style: t.monoLabel,
            ),
            trailing: Icon(_iconFor(file.name), color: t.textSecondary),
            onTap: () => _toggleSelection(file.path),
          ),
        ),
      ),
    );
  }

  String _subtitle(PrinterFile file) {
    final size = formatBytes(file.size);
    final date = file.modifiedAt;
    if (date == null) return size;
    // Already local — [dateTimeFromJson] converts once, at parse time.
    return '$size · ${DateTimeFormats.of(context).dateTime(date)}';
  }

  /// Whether a server-side preparation is still running — the only phase that
  /// can be cancelled, and the one where the counts mean files rather than
  /// bytes.
  bool get _preparing {
    final state = _job?.state;
    return state != null && !state.isTerminal;
  }

  /// What the selection row says while something is running: which phase the
  /// wait is in. Null when nothing is, and the row goes back to the count.
  ///
  /// The legacy path has no phase to report — it is one held request — so it
  /// shows the transfer wording throughout, which is what it is doing as far as
  /// this screen can tell.
  String? _phaseLabel(AppLocalizations l10n) {
    if (!_busy) return null;
    return _preparing ? l10n.pfmPreparingOnServer : l10n.pfmDownloading;
  }

  /// The figure beside the spinner: files staged while the server prepares,
  /// per cent once bytes are moving. Null while neither is countable.
  String? _progressLabel() {
    final job = _job;
    if (_preparing && job != null) {
      return job.requested > 1
          ? '${job.successful + job.failed}/${job.requested}'
          : null;
    }
    final progress = _downloadProgress;
    return progress == null ? null : '${(progress * 100).round()}%';
  }

  Widget _actionBar(AppLocalizations l10n, DashTokens t) => DecoratedBox(
        decoration: BoxDecoration(
          color: t.navBar,
          border: Border(top: BorderSide(color: t.hairline)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  // A live region so a screen reader says the phase changed:
                  // the row is the only place that distinguishes waiting for
                  // the server from waiting for the transfer, and a change of
                  // text alone is announced to nobody.
                  child: Semantics(
                    liveRegion: _busy,
                    child: Text(
                      _phaseLabel(l10n) ?? l10n.pfmSelected(_selected.length),
                      style: t.body.copyWith(color: t.textSecondary),
                      // Two lines because the phase wording is a sentence, not
                      // a count: "Przygotowywanie na serwerze…" is cut to
                      // "Przygotowywa…" on one line at the larger system text
                      // sizes, and the bar can afford the height.
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                if (_busy)
                  Padding(
                    padding: EdgeInsets.only(
                      left: 8,
                      right: _preparing ? 0 : 16,
                    ),
                    child: Row(
                      children: [
                        if (_progressLabel() case final label?)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Text(label, style: t.monoLabel),
                          ),
                        DashSpinner(size: 20, value: _downloadProgress),
                        // Only while the server is still pulling files. Once
                        // the transfer starts there is nothing worth stopping:
                        // the bytes are coming off the server's own disk, and
                        // the token is already spent.
                        //
                        // Disabled rather than removed once pressed. It has to
                        // stop looking pressable straight away — the DELETE and
                        // the poll it interrupts both take a moment — but a
                        // control that vanishes under the finger takes screen-
                        // reader focus with it, back to the top of the route.
                        if (_preparing)
                          logTag(
                            'printer_files.download_cancel',
                            IconButton(
                              onPressed:
                                  _cancelRequested ? null : _cancelPreparation,
                              tooltip: l10n.cancel,
                              icon: const Icon(Icons.close),
                              color: t.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  )
                else ...[
                  logTag(
                    'printer_files.download',
                    TextButton.icon(
                      onPressed: _download,
                      style:
                          TextButton.styleFrom(foregroundColor: t.accentGreenInk),
                      icon: const Icon(Icons.download),
                      label: Text(l10n.pfmDownload),
                    ),
                  ),
                  const SizedBox(width: 4),
                  logTag(
                    'printer_files.delete',
                    TextButton.icon(
                      onPressed: _delete,
                      style: TextButton.styleFrom(foregroundColor: t.danger),
                      icon: const Icon(Icons.delete_outline),
                      label: Text(l10n.pfmDelete),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );

  Widget _centered({
    required IconData icon,
    required String message,
    required DashTokens tokens,
    Widget? action,
  }) =>
      Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: tokens.textTertiary),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: tokens.bodySoft,
              ),
              if (action != null) ...[const SizedBox(height: 16), action],
            ],
          ),
        ),
      );
}

enum _QuickTab { root, cache, models, timelapse }


/// Rough icon by extension — matches the file types printers store.
IconData _iconFor(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  return switch (ext) {
    '3mf' || 'gcode' || 'stl' => Icons.view_in_ar,
    'mp4' || 'avi' || 'mov' => Icons.movie_outlined,
    'png' || 'jpg' || 'jpeg' || 'gif' => Icons.image_outlined,
    'zip' || 'gz' || 'tar' => Icons.folder_zip_outlined,
    'json' || 'txt' || 'log' || 'cfg' => Icons.description_outlined,
    _ => Icons.insert_drive_file_outlined,
  };
}
