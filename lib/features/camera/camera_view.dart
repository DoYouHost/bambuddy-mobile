import 'dart:io' show HttpException;

import 'package:flutter/material.dart';
import 'package:flutter_mjpeg/flutter_mjpeg.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/endpoints.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';

/// Full-screen camera view (MJPEG). Stream lives only while screen is
/// mounted: `Mjpeg` closes connection on `dispose` (pop route), and built-in
/// `visibility_detector` pauses when screen is obscured.
///
/// Stream token (~60 min) from [cameraTokenProvider]; on 401 (expiry)
/// once force re-mint and restart stream.
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
  /// Token for which we already forced re-mint after 401 — protects against
  /// refresh loop if error doesn't stem from expired token.
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
      // Stream can be slow on remote connection — give more than default 5s.
      timeout: const Duration(seconds: 15),
      loading: (_) => _Loading(text: l10n.cameraConnecting),
      error: (context, error, _) {
        // 401 = token expired → once force re-mint and restart stream.
        // Anchored on `flutter_mjpeg`'s own `HttpException('Stream returned
        // $statusCode status')` — not a raw substring match on
        // `error.toString()` — since a server on a port containing "401"
        // (e.g. `host:8401`) would otherwise make a routine connectivity
        // error (whose message embeds the address) look like an expired
        // token, burning the one-shot re-mint on every hiccup.
        if (_isTokenExpired(error) && _remintedFor != token) {
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

/// `flutter_mjpeg` throws `HttpException('Stream returned $statusCode
/// status')` for any non-2xx response — matches only that shape, not any
/// error whose `toString()` happens to contain "401".
bool _isTokenExpired(Object error) {
  if (error is! HttpException) return false;
  final m = RegExp(r'^Stream returned (\d+) status$').firstMatch(error.message);
  return m?.group(1) == '401';
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
