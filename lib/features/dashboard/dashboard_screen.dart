import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers.dart';
import 'providers.dart';
import 'widgets/connection_banner.dart';
import 'widgets/printer_card.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Wygaśnięcie sesji → łagodny powrót do konfiguracji,
    // nigdy crash ani martwy dashboard.
    ref.listen(dashboardProvider.select((s) => s.authExpired),
        (_, expired) {
      if (expired) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sesja wygasła — zaloguj się ponownie'),
          ),
        );
        context.go('/setup');
      }
    });

    final state = ref.watch(dashboardProvider);
    final profile = ref.watch(serverProfileProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Drukarki'),
        actions: [
          IconButton(
            tooltip: 'Zmień serwer',
            icon: const Icon(Icons.settings),
            onPressed: () => _confirmChangeServer(context, ref),
          ),
        ],
        bottom: profile == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(18),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    profile.label ?? profile.baseUrl,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
      ),
      body: Column(
        children: [
          if (state.stale)
            ConnectionBanner(
              message: 'Serwer nieosiągalny — dane mogą być nieaktualne',
            ),
          Expanded(child: _body(context, ref, state)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, DashboardState state) {
    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    // Pierwsze ładowanie padło — nie ma czego pokazać poza błędem.
    if (state.printers == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 48),
              const SizedBox(height: 12),
              Text(state.error ?? 'Nie udało się połączyć z serwerem',
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () =>
                    ref.read(dashboardProvider.notifier).refresh(),
                child: const Text('Spróbuj ponownie'),
              ),
            ],
          ),
        ),
      );
    }

    final printers = state.printers!;
    return RefreshIndicator(
      onRefresh: () => ref.read(dashboardProvider.notifier).refresh(),
      child: printers.isEmpty
          ? ListView(
              children: const [
                Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: Text('Brak drukarek — dodaj je na serwerze'),
                  ),
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: printers.length,
              itemBuilder: (_, i) => PrinterCard(item: printers[i]),
            ),
    );
  }

  Future<void> _confirmChangeServer(
      BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Zmienić serwer?'),
        content: const Text(
            'Zapisany profil i poświadczenia zostaną usunięte.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Zmień'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref.read(serverProfileProvider.notifier).clear();
    }
  }
}
