import 'package:flutter/material.dart';
import 'package:flutter_mjpeg/flutter_mjpeg.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/endpoints.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';

/// Pełnoekranowy podgląd kamery (MJPEG). Strumień żyje tylko póki ekran jest
/// zamontowany: `Mjpeg` zamyka połączenie w `dispose` (pop trasy), a wbudowany
/// `visibility_detector` pauzuje go, gdy ekran zostaje przykryty.
///
/// Token strumienia (~60 min) bierzemy z [cameraTokenProvider]; po 401
/// (wygaśnięcie) raz wymuszamy re-mint i restart strumienia.
class CameraView extends ConsumerStatefulWidget {
  const CameraView({
    super.key,
    required this.printerId,
    required this.printerName,
  });

  final int printerId;
  final String printerName;

  @override
  ConsumerState<CameraView> createState() => _CameraViewState();
}

class _CameraViewState extends ConsumerState<CameraView> {
  /// Token, dla którego już raz wymusiliśmy re-mint po 401 — chroni przed
  /// pętlą odświeżania, gdy błąd nie wynika z wygasłego tokenu.
  String? _remintedFor;

  void _retry() {
    setState(() => _remintedFor = null);
    ref.read(cameraTokenServiceProvider).invalidate();
    ref.invalidate(cameraTokenProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final baseUrl = ref.watch(serverProfileProvider)?.baseUrl;
    final tokenAsync = ref.watch(cameraTokenProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.printerName),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: baseUrl == null
            ? _Message(text: l10n.cameraError, onRetry: _retry)
            : tokenAsync.when(
                loading: () => _Loading(text: l10n.cameraConnecting),
                error: (_, _) => _Message(text: l10n.cameraError, onRetry: _retry),
                data: (token) => _stream(baseUrl, token, l10n),
              ),
      ),
    );
  }

  Widget _stream(String baseUrl, String token, AppLocalizations l10n) {
    final url =
        '$baseUrl${Endpoints.cameraStream(widget.printerId)}?token=$token';
    return Mjpeg(
      stream: url,
      isLive: true,
      fit: BoxFit.contain,
      // Strumień bywa wolny na łączu zdalnym — dajemy więcej niż domyślne 5 s.
      timeout: const Duration(seconds: 15),
      loading: (_) => _Loading(text: l10n.cameraConnecting),
      error: (context, error, _) {
        // 401 = token wygasł → jednorazowy re-mint i restart strumienia.
        if (error.toString().contains('401') && _remintedFor != token) {
          _remintedFor = token;
          Future.microtask(() {
            if (!mounted) return;
            ref.read(cameraTokenServiceProvider).invalidate();
            ref.invalidate(cameraTokenProvider);
          });
          return _Loading(text: l10n.cameraConnecting);
        }
        return _Message(text: l10n.cameraError, onRetry: _retry);
      },
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(color: Colors.white),
        const SizedBox(height: 16),
        Text(text, style: const TextStyle(color: Colors.white70)),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, required this.onRetry});

  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.videocam_off, color: Colors.white54, size: 48),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: Text(l10n.retry)),
        ],
      ),
    );
  }
}
