import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/dash_theme.dart';
import 'package:app_diagnostics/app_diagnostics.dart';
import '../../core/api/endpoints.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import 'mjpeg_view.dart';

/// Full-screen camera view (MJPEG). Stream lives only while screen is
/// mounted: [MjpegView] closes the connection on `dispose` (pop route) and
/// while the app is in the background.
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
    final profile = ref.watch(serverProfileProvider);
    final baseUrl = profile?.baseUrl;
    final tokenAsync = ref.watch(cameraTokenProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: loggedAppBar(
        AppBar(
          title: Text(widget.printerName),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
        ),
      ),
      body: Center(
        // No MJPEG source exists in demo mode — explain instead of erroring.
        child: profile?.isDemo == true
            ? _DemoUnavailable(text: l10n.cameraDemoUnavailable)
            : baseUrl == null
            ? _Message(text: l10n.cameraError, onRetry: _retry)
            : tokenAsync.when(
                loading: () => _Loading(text: l10n.cameraConnecting),
                error: (_, _) =>
                    _Message(text: l10n.cameraError, onRetry: _retry),
                data: (token) => _stream(baseUrl, token, l10n),
              ),
      ),
    );
  }

  Widget _stream(String baseUrl, String token, AppLocalizations l10n) {
    final url =
        '$baseUrl${Endpoints.cameraStream(widget.printerId)}?token=$token';
    return MjpegView(
      url: url,
      fit: BoxFit.contain,
      loading: (_) => _Loading(text: l10n.cameraConnecting),
      retrying: (_) => const _Retrying(),
      error: (context, error) {
        // 401 = token expired -> once force re-mint and restart stream.
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

bool _isTokenExpired(Object error) =>
    error is MjpegHttpStatus && error.status == 401;

class _DemoUnavailable extends StatelessWidget {
  const _DemoUnavailable({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
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
        ],
      ),
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

/// Sits in the corner of the last frame while the stream is being retried. The
/// picture is frozen but still worth more than an error message a blip will
/// outlive — this is what says so.
class _Retrying extends StatelessWidget {
  const _Retrying();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: AppLocalizations.of(context).cameraConnecting,
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(8),
        decoration: const BoxDecoration(
          color: Colors.black54,
          shape: BoxShape.circle,
        ),
        child: const SizedBox.square(
          dimension: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
        ),
      ),
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
          FilledButton(
            onPressed: onRetry,
            child: Text(l10n.retry),
          ).tagged('camera.retry'),
        ],
      ),
    );
  }
}
