import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/endpoints.dart';
import '../../providers.dart';

/// Miniatura wydruku z archiwum (kolejka + archiwum). Uwierzytelnia się przez
/// `?token=` (token kamery) — nagłówek auth NIE działa dla tego zasobu,
/// zweryfikowane na żywo. Wzorzec identyczny jak okładka w printer_card.
/// Placeholder zamiast błędu — nigdy nie wywraca karty.
///
/// Renderowane miniatury mają sporo pustego marginesu wokół modelu, więc
/// skalujemy zawartość ([zoom], domyślnie 140%) wewnątrz przycięcia, by
/// „dokadrować" wydruk i wypełnić kafelek.
class PrintThumbnail extends ConsumerWidget {
  const PrintThumbnail({
    super.key,
    required this.archiveId,
    this.size = 52,
    this.zoom = 1.4,
  });

  /// Id archiwum; gdy null → placeholder (np. element kolejki bez archiwum).
  final int? archiveId;
  final double size;

  /// Współczynnik powiększenia zawartości miniatury (crop pustego marginesu).
  final double zoom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(size < 64 ? 8 : 10);

    Widget placeholder([IconData icon = Icons.image_outlined]) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: radius,
          ),
          child: Icon(icon, color: scheme.onSurfaceVariant, size: size * 0.4),
        );

    final id = archiveId;
    final baseUrl = ref.watch(serverProfileProvider)?.baseUrl;
    if (id == null || baseUrl == null) return placeholder();

    return ref.watch(cameraTokenProvider).when(
          loading: placeholder,
          error: (_, _) => placeholder(Icons.broken_image_outlined),
          data: (token) => ClipRRect(
            borderRadius: radius,
            child: Transform.scale(
              scale: zoom,
              child: Image.network(
                '$baseUrl${Endpoints.archiveThumbnail(id)}?token=$token',
                width: size,
                height: size,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) =>
                    placeholder(Icons.broken_image_outlined),
                loadingBuilder: (_, child, progress) =>
                    progress == null ? child : placeholder(),
              ),
            ),
          ),
        );
  }
}
