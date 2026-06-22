import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/models/printer.dart';
import '../../core/models/queue_item.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import '../common/print_thumbnail.dart';
import 'queue_providers.dart';

/// Ekran kolejki wydruków (M5): przeciąganie (reorder), swipe-to-delete za
/// potwierdzeniem, akcje start/anuluj. Pokazuje tylko elementy aktywne.
///
/// Kolejka nie ma WS, a stan zmienia się też poza apką (np. wydruk wystartowany
/// z drukarki/innego klienta), więc gdy ekran żyje na pierwszym planie dociągamy
/// świeżą listę cyklicznie. Timer milknie w tle (jak polling Dashboardu), bo to
/// niepotrzebne bicie po serwerze — powrót i tak robi świeży fetch.
class QueueScreen extends ConsumerStatefulWidget {
  const QueueScreen({super.key});

  @override
  ConsumerState<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends ConsumerState<QueueScreen> {
  /// Częstotliwość auto-odświeżania na pierwszym planie. Rzadziej niż roster
  /// Dashboardu (5 s) — kolejka zmienia się wolniej, a fetch jest cięższy.
  static const _refreshInterval = Duration(seconds: 10);

  Timer? _timer;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _startTimer();
    _lifecycle = AppLifecycleListener(
      onPause: _stopTimer,
      onResume: () {
        // Powrót na pierwszy plan: natychmiast dociągnij i wznów cykl.
        unawaited(ref.read(queueProvider.notifier).refresh());
        _startTimer();
      },
    );
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(
      _refreshInterval,
      (_) => unawaited(ref.read(queueProvider.notifier).refresh()),
    );
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _stopTimer();
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(queueProvider);

    // Wydruki oczekujące (poza aktualnie drukowanymi) — od ich obecności
    // zależy widoczność przycisku „uruchom następny".
    final items = async.valueOrNull ?? const <QueueItem>[];
    final queued = [
      for (final i in items)
        if (i.statusKind != QueueItemStatusKind.printing) i,
    ];
    final firstQueued = queued.isEmpty ? null : queued.first;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.navQueue)),
      floatingActionButton: firstQueued == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _startNext(context, ref, firstQueued, l10n),
              icon: const Icon(Icons.play_arrow),
              label: Text(l10n.queueStartNext),
            ),
      body: async.when(
        skipLoadingOnReload: true,
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => _ErrorView(
          message: err is AppApiException
              ? err.localized(l10n)
              : l10n.connectFailed,
          onRetry: () => ref.read(queueProvider.notifier).refresh(),
          retryLabel: l10n.retry,
        ),
        data: (items) => RefreshIndicator(
          onRefresh: () => ref.read(queueProvider.notifier).refresh(),
          child: items.isEmpty
              ? _EmptyView(message: l10n.queueEmpty)
              : _QueueList(items: items),
        ),
      ),
    );
  }

  /// „Uruchom następny": bierze pierwszy oczekujący wydruk, pyta o wolną
  /// drukarkę i startuje go na niej (przypisanie + start). Uruchamia fizyczny
  /// wydruk.
  Future<void> _startNext(
    BuildContext context,
    WidgetRef ref,
    QueueItem item,
    AppLocalizations l10n,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final List<Printer> free;
    try {
      free = await ref.read(freePrintersProvider.future);
    } on AppApiException {
      messenger.showSnackBar(SnackBar(content: Text(l10n.ctrlFailed)));
      return;
    }
    if (!context.mounted) return;
    if (free.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.queueNoFreePrinters)));
      return;
    }

    final printer = await showModalBottomSheet<Printer>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(l10n.pickPrinterTitle,
                  style: Theme.of(ctx).textTheme.titleMedium),
            ),
            for (final p in free)
              ListTile(
                leading: const Icon(Icons.print_outlined),
                title: Text(p.name),
                subtitle: p.model == null ? null : Text(p.model!),
                onTap: () => Navigator.pop(ctx, p),
              ),
          ],
        ),
      ),
    );
    if (printer == null) return;

    final result =
        await ref.read(queueProvider.notifier).startOnPrinter(item.id, printer.id);
    if (result == QueueActionResult.ok) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.queuePrintStarted)));
    } else {
      _snackForResult(messenger, l10n, result);
    }
  }
}

class _QueueList extends ConsumerWidget {
  const _QueueList({required this.items});

  final List<QueueItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // Drukujące przypięte na górze (nieprzesuwalne, poza ReorderableListView);
    // reszta reorderowalna. Indeksy reorderu przesuwamy o liczbę przypiętych,
    // bo notifier operuje na pełnej liście aktywnych (drukujące + reszta).
    final pinned = [
      for (final i in items)
        if (i.statusKind == QueueItemStatusKind.printing) i,
    ];
    final reorderable = [
      for (final i in items)
        if (i.statusKind != QueueItemStatusKind.printing) i,
    ];
    final offset = pinned.length;

    return Column(
      children: [
        for (final it in pinned) _QueueCard(item: it, pinned: true),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 6),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: reorderable.length,
            onReorderItem: (oldIndex, newIndex) async {
              final messenger = ScaffoldMessenger.of(context);
              final result = await ref
                  .read(queueProvider.notifier)
                  .reorder(oldIndex + offset, newIndex + offset);
              _snackForResult(messenger, l10n, result);
            },
            itemBuilder: (context, i) => _QueueCard(
              key: ValueKey(reorderable[i].id),
              item: reorderable[i],
            ),
          ),
        ),
      ],
    );
  }
}

class _QueueCard extends ConsumerWidget {
  const _QueueCard({super.key, required this.item, this.pinned = false});

  final QueueItem item;

  /// Element drukujący: przypięty na górze, wyróżniony, nieprzesuwalny i bez
  /// swipe-to-delete (nie wrapujemy w Dismissible).
  final bool pinned;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    final card = Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      // Drukujące wyróżniamy obramowaniem (outline), nie wypełnieniem tła.
      shape: pinned
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.colorScheme.primary, width: 1.5),
            )
          : null,
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        leading: PrintThumbnail(archiveId: item.archiveId),
        title: Text(
          item.archiveName ?? '#${item.id}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: _Subtitle(item: item),
        trailing: _QueueActions(item: item),
      ),
    );

    // Drukujące: bez Dismissible — nie da się ich usunąć swipe'em (i są poza
    // ReorderableListView, więc nieprzesuwalne).
    if (pinned) return card;

    return Dismissible(
      key: ValueKey('dismiss_${item.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.delete_outline,
            color: theme.colorScheme.onErrorContainer),
      ),
      // Dialog tylko TU; faktyczne usunięcie w onDismissed (notifier usuwa
      // element ze stanu) — inaczej Dismissible kłóci się z przebudową listy.
      confirmDismiss: (_) => _confirmDelete(context, l10n),
      onDismissed: (_) async {
        final messenger = ScaffoldMessenger.of(context);
        final result = await ref.read(queueProvider.notifier).delete(item.id);
        _snackForResult(messenger, l10n, result);
      },
      child: card,
    );
  }

  Future<bool?> _confirmDelete(BuildContext context, AppLocalizations l10n) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.queueDeleteTitle),
        content: Text(l10n.queueDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.queueDeleteConfirm),
          ),
        ],
      ),
    );
  }
}

class _Subtitle extends StatelessWidget {
  const _Subtitle({required this.item});

  final QueueItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final parts = <String>[
      if (item.printerName != null) item.printerName!,
      if (item.printTimeSeconds != null) _eta(l10n, item.printTimeSeconds!),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatusChip(item: item),
          if (parts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                parts.join(' · '),
                style: theme.textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  String _eta(AppLocalizations l10n, int seconds) {
    final minutes = seconds ~/ 60;
    if (minutes < 60) return l10n.durationMinutes(minutes);
    return l10n.durationHoursMinutes(minutes ~/ 60, minutes % 60);
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.item});

  final QueueItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = switch (item.statusKind) {
      QueueItemStatusKind.printing => (l10n.queueStatusPrinting, scheme.primary),
      QueueItemStatusKind.paused => (l10n.queueStatusPaused, scheme.tertiary),
      QueueItemStatusKind.scheduled => (
          l10n.queueStatusScheduled,
          scheme.secondary
        ),
      QueueItemStatusKind.pending => (
          l10n.queueStatusPending,
          scheme.onSurfaceVariant
        ),
      _ => (item.status, scheme.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _QueueActions extends ConsumerWidget {
  const _QueueActions({required this.item});

  final QueueItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // Drukujący element nie ma sensu „startować"; każdy aktywny można anulować.
    final canStart = item.statusKind == QueueItemStatusKind.pending ||
        item.statusKind == QueueItemStatusKind.scheduled;

    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      onSelected: (value) async {
        final messenger = ScaffoldMessenger.of(context);
        final notifier = ref.read(queueProvider.notifier);
        final result = switch (value) {
          'start' => await notifier.start(item.id),
          'cancel' => await notifier.cancel(item.id),
          _ => QueueActionResult.error,
        };
        _snackForResult(messenger, l10n, result);
      },
      itemBuilder: (_) => [
        if (canStart)
          PopupMenuItem(
            value: 'start',
            child: ListTile(
              leading: const Icon(Icons.play_arrow),
              title: Text(l10n.queueStart),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        PopupMenuItem(
          value: 'cancel',
          child: ListTile(
            leading: const Icon(Icons.stop_circle_outlined),
            title: Text(l10n.queueCancel),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    // ListView, by RefreshIndicator działał także przy pustym stanie.
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(48),
          child: Column(
            children: [
              Icon(Icons.playlist_add_check,
                  size: 48, color: Theme.of(context).disabledColor),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
            ],
          ),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.onRetry,
    required this.retryLabel,
  });

  final String message;
  final VoidCallback onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: Text(retryLabel)),
          ],
        ),
      ),
    );
  }
}

/// Wspólny SnackBar dla wyników akcji kolejki (forbidden/error → komunikat;
/// ok → cisza, bo zmiana jest widoczna w UI).
void _snackForResult(
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
  QueueActionResult result,
) {
  final text = switch (result) {
    QueueActionResult.ok => null,
    QueueActionResult.forbidden => l10n.ctrlForbidden,
    QueueActionResult.error => l10n.ctrlFailed,
  };
  if (text == null) return;
  messenger.showSnackBar(SnackBar(content: Text(text)));
}
