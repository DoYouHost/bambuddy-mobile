import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:app_diagnostics/app_diagnostics.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/api/endpoints.dart';
import '../../core/models/library_file_detail.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/server_refusal.dart';
import '../../providers.dart';
import '../common/api_failure_snack.dart';
import '../common/dash_async.dart';
import '../common/device_files.dart';
import '../common/media_image.dart';
import '../common/photo_pager.dart';
import '../common/prompt_name_dialog.dart';
import 'file_manager_providers.dart';

/// Route of [FileDetailsScreen]; [name] is only the bar title.
String fileDetailsRoute(int fileId, {String? name}) =>
    Uri(path: '/files/$fileId', queryParameters: {'name': ?name}).toString();

String _filePhotosRoute(int fileId, int start, String? name) => Uri(
  path: '/files/$fileId/photos',
  queryParameters: {'start': '$start', 'name': ?name},
).toString();

/// Photos of the printed result, a link and notes on one library file (#3077).
///
/// Offered only where the listing carries `photo_count`, so every route here
/// exists. Writes are not pre-checked against permissions: a session that may
/// not change the file gets the server's 403, as rename and delete do.
class FileDetailsScreen extends ConsumerStatefulWidget {
  const FileDetailsScreen({super.key, required this.fileId, this.title});

  final int fileId;
  final String? title;

  @override
  ConsumerState<FileDetailsScreen> createState() => _FileDetailsScreenState();
}

class _FileDetailsScreenState extends ConsumerState<FileDetailsScreen> {
  bool _uploading = false;

  AppLocalizations get _l10n => AppLocalizations.of(context);

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n;
    final detail = ref.watch(libraryFileDetailProvider(widget.fileId));
    return Scaffold(
      appBar: dashAppBar(context, title: widget.title ?? l10n.fmFileDetails),
      body: dashAsync(
        context,
        detail,
        onRetry: () => ref.invalidate(libraryFileDetailProvider(widget.fileId)),
        data: (d) => ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            _photos(l10n, d),
            const Divider(),
            _linkTile(l10n, d),
            if (d.sourceUrl != null && d.sourceUrl!.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.public),
                title: Text(l10n.fmSource),
                subtitle: Text(d.sourceUrl!, maxLines: 2),
                onTap: () => _open(d.sourceUrl!),
              ).tagged('file_details.source'),
            _notesTile(l10n, d),
          ],
        ),
      ),
    );
  }

  Widget _photos(AppLocalizations l10n, LibraryFileDetail d) {
    final t = DashTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(l10n.archivePhotosTitle, style: t.titleSm)),
              logTag(
                'file_details.add_photo',
                TextButton.icon(
                  onPressed: _uploading ? null : _addPhoto,
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: Text(l10n.fmPhotoAdd),
                ),
              ),
            ],
          ),
          if (_uploading) const LinearProgressIndicator(),
          const SizedBox(height: 8),
          if (d.photos.isEmpty)
            Text(
              l10n.fmPhotosEmpty,
              style: t.bodyPlain.copyWith(color: t.textTertiary),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (i, name) in d.photos.indexed)
                  logTag(
                    'file_details.photo',
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => context.push(
                        _filePhotosRoute(widget.fileId, i, widget.title),
                      ),
                      child: MediaImage(
                        path: Endpoints.libraryFilePhoto(widget.fileId, name),
                        width: 96,
                        height: 96,
                        borderRadius: BorderRadius.circular(12),
                        placeholder: (_) => SizedBox.square(
                          dimension: 96,
                          child: Icon(
                            Icons.image_outlined,
                            color: t.textTertiary,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _linkTile(AppLocalizations l10n, LibraryFileDetail d) {
    final url = d.externalUrl;
    final hasUrl = url != null && url.isNotEmpty;
    return ListTile(
      leading: const Icon(Icons.link),
      title: Text(l10n.fmLink),
      subtitle: Text(hasUrl ? url : l10n.fmLinkNone, maxLines: 2),
      onTap: hasUrl ? () => _open(url) : () => _editLink(d),
      trailing: logTag(
        'file_details.edit_link',
        IconButton(
          tooltip: l10n.fmLinkEdit,
          icon: const Icon(Icons.edit_outlined),
          onPressed: () => _editLink(d),
        ),
      ),
    ).tagged('file_details.link');
  }

  Widget _notesTile(AppLocalizations l10n, LibraryFileDetail d) {
    final notes = d.notes;
    final hasNotes = notes != null && notes.isNotEmpty;
    return ListTile(
      leading: const Icon(Icons.notes),
      title: Text(l10n.fmNotes),
      subtitle: Text(hasNotes ? notes : l10n.fmNotesNone),
      onTap: () => _editNotes(d),
      trailing: logTag(
        'file_details.edit_notes',
        IconButton(
          tooltip: l10n.fmNotesEdit,
          icon: const Icon(Icons.edit_outlined),
          onPressed: () => _editNotes(d),
        ),
      ),
    ).tagged('file_details.notes');
  }

  /// Only web links leave the app: the server refuses any other scheme on
  /// write, but a row written before that check, or by an older build, is not
  /// something to hand to the system as an intent.
  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    final web = uri != null && (uri.isScheme('http') || uri.isScheme('https'));
    final opened =
        web && await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).snack(_l10n.fmLinkOpenFailed);
    }
  }

  Future<void> _editLink(LibraryFileDetail d) async {
    final url = await promptName(
      context,
      title: _l10n.fmLinkEdit,
      label: _l10n.fmLinkField,
      initial: d.externalUrl,
      id: 'file_details.link_prompt',
      allowEmpty: true,
      keyboardType: TextInputType.url,
    );
    if (url == null || !mounted) return;
    await _write(
      () => ref.read(libraryRepositoryProvider).setFileLink(widget.fileId, url),
      done: _l10n.fmLinkSaved,
      action: 'file_details.edit_link',
    );
  }

  Future<void> _editNotes(LibraryFileDetail d) async {
    final notes = await promptName(
      context,
      title: _l10n.fmNotesEdit,
      label: _l10n.fmNotes,
      initial: d.notes,
      id: 'file_details.notes_prompt',
      allowEmpty: true,
      maxLines: 6,
      keyboardType: TextInputType.multiline,
    );
    if (notes == null || !mounted) return;
    await _write(
      () => ref
          .read(libraryRepositoryProvider)
          .setFileNotes(widget.fileId, notes),
      done: _l10n.fmNotesSaved,
      action: 'file_details.edit_notes',
    );
  }

  Future<void> _addPhoto() async {
    final source = await _pickSource();
    if (source == null || !mounted) return;
    final ({String path, String name})? photo;
    try {
      photo = await _takePhoto(source);
    } on PlatformException {
      if (mounted) ScaffoldMessenger.of(context).snack(_l10n.fmPhotoPickFailed);
      return;
    }
    if (photo == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      await _write(
        () => ref
            .read(libraryRepositoryProvider)
            .addFilePhoto(
              widget.fileId,
              filePath: photo!.path,
              filename: photo.name,
            ),
        done: _l10n.fmPhotoAdded,
        action: 'file_details.add_photo',
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<_PhotoSource?> _pickSource() => dashSheet<_PhotoSource>(
    context,
    scrollControlled: false,
    builder: (ctx) {
      final l10n = AppLocalizations.of(ctx);
      return logTag(
        'sheet.photo_source',
        SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: Text(l10n.fmPhotoFromCamera),
                onTap: () => Navigator.pop(ctx, _PhotoSource.camera),
              ).tagged('photo_source.camera'),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: Text(l10n.fmPhotoFromGallery),
                onTap: () => Navigator.pop(ctx, _PhotoSource.gallery),
              ).tagged('photo_source.gallery'),
              ListTile(
                leading: const Icon(Icons.folder_open_outlined),
                title: Text(l10n.fmPhotoFromFiles),
                onTap: () => Navigator.pop(ctx, _PhotoSource.files),
              ).tagged('photo_source.files'),
            ],
          ),
        ),
      );
    },
  );

  /// The picked photo as a local path plus a name with its extension, or null
  /// when the user backed out. A picker that fails throws [PlatformException].
  Future<({String path, String name})?> _takePhoto(_PhotoSource source) async {
    if (source == _PhotoSource.files) {
      final picked = await pickFileFromDevice(
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
      );
      final file = picked.file;
      if (picked.outcome == DeviceFileOutcome.failed ||
          (file != null && file.path.isEmpty)) {
        throw PlatformException(code: 'pick_failed');
      }
      return file == null ? null : (path: file.path, name: file.name);
    }
    final shot = await ImagePicker().pickImage(
      source: source == _PhotoSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
    );
    return shot == null ? null : (path: shot.path, name: shot.name);
  }

  /// Runs one write, then re-reads this file and the listing whose badges
  /// show what it carries — through the container, so a screen left while
  /// the write was out still leaves the badges right.
  Future<void> _write(
    Future<void> Function() body, {
    required String done,
    required String action,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final providers = ProviderScope.containerOf(context, listen: false);
    final l10n = _l10n;
    try {
      await body();
    } on AppApiException catch (e) {
      showApiFailure(
        mounted ? messenger : null,
        e,
        l10n,
        action: action,
        message: fileWriteMessage(l10n, e),
      );
      return;
    }
    messenger.snack(done);
    await _reread(providers, widget.fileId);
  }
}

enum _PhotoSource { camera, gallery, files }

Future<void> _reread(ProviderContainer providers, int fileId) {
  providers.invalidate(libraryFileDetailProvider(fileId));
  return providers.read(fileManagerProvider.notifier).refresh();
}

/// What to say when a photo, link or notes write was refused.
String fileWriteMessage(AppLocalizations l10n, AppApiException e) =>
    e is ApiException && e.statusCode == 413
    ? l10n.fmPhotoErrTooLarge
    : serverRefusal(l10n, e, _fileWriteRefusals);

final _fileWriteRefusals = <RefusalRule>[
  (['must be an image'], (l10n) => l10n.fmPhotoErrType),
  (['http://', 'https://'], (l10n) => l10n.fmLinkErrScheme),
];

/// A library file's photos full-screen, swiped through from [start], with the
/// one on screen deletable.
class FilePhotosScreen extends ConsumerStatefulWidget {
  const FilePhotosScreen({
    super.key,
    required this.fileId,
    this.start = 0,
    this.title,
  });

  final int fileId;
  final int start;
  final String? title;

  @override
  ConsumerState<FilePhotosScreen> createState() => _FilePhotosScreenState();
}

class _FilePhotosScreenState extends ConsumerState<FilePhotosScreen> {
  late int _page = widget.start;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final detail = ref.watch(libraryFileDetailProvider(widget.fileId));
    final photos = detail.valueOrNull?.photos ?? const <String>[];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: photoViewerAppBar(
        widget.title ?? l10n.archivePhotosTitle,
        actions: [
          if (photos.isNotEmpty)
            logTag(
              'file_photos.delete',
              IconButton(
                tooltip: l10n.fmPhotoDelete,
                icon: const Icon(Icons.delete_outline),
                onPressed: () =>
                    _delete(photos[_page.clamp(0, photos.length - 1)]),
              ),
            ),
        ],
      ),
      body: dashAsync(
        context,
        detail,
        onRetry: () => ref.invalidate(libraryFileDetailProvider(widget.fileId)),
        data: (d) => d.photos.isEmpty
            ? EmptyStateView(
                message: l10n.fmPhotosEmpty,
                icon: Icons.photo_camera_outlined,
              )
            : PhotoPager(
                // A new key per list rebuilds the pager on `_page`, so the page
                // shown and the one the delete button names never part.
                key: ValueKey(d.photos.join('/')),
                paths: [
                  for (final name in d.photos)
                    Endpoints.libraryFilePhoto(widget.fileId, name),
                ],
                // Kept inside the list, so a later list does not reopen past
                // the photo that took the deleted one's place.
                initialPage: _page = _page.clamp(0, d.photos.length - 1),
                onPageChanged: (i) => _page = i,
              ),
      ),
    );
  }

  Future<void> _delete(String name) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final providers = ProviderScope.containerOf(context, listen: false);
    final confirmed = await confirmDialog(
      context,
      title: l10n.fmPhotoDelete,
      message: l10n.fmPhotoDeleteConfirm,
      confirmLabel: l10n.fmDelete,
      destructive: true,
      id: 'file_photos.delete',
    );
    if (!confirmed || !mounted) return;
    try {
      await ref
          .read(libraryRepositoryProvider)
          .deleteFilePhoto(widget.fileId, name);
    } on AppApiException catch (e) {
      showApiFailure(
        mounted ? messenger : null,
        e,
        l10n,
        action: 'file_photos.delete',
      );
      return;
    }
    messenger.snack(l10n.fmPhotoDeleted);
    await _reread(providers, widget.fileId);
  }
}
