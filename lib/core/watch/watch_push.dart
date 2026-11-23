import 'dart:async';

import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import '../../providers.dart';
import '../theme/appearance_providers.dart';

/// What [pushConfigToWatch] reads providers with: `ref.read`, or a container's.
typedef ProviderReader = T Function<T>(ProviderListenable<T> provider);

/// Hands the phone's server, theme and TLS identity, the Cloudflare Access
/// credential included, to a paired watch. Best-effort, and a no-op without a
/// server profile. A function of its own so a test can see what it sends: the
/// watch has no way to set any of it up, and goes without whatever is left out.
void pushConfigToWatch(ProviderReader read) {
  final profile = read(serverProfileProvider);
  if (profile == null) return;
  unawaited(
    read(watchConfigSyncProvider).push(
      profile,
      theme: read(watchThemeProvider),
      ca: read(customCaProvider),
      clientCert: read(clientCertProvider),
      edge: read(edgeAccessProvider),
    ),
  );
}
