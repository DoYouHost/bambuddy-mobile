import 'package:bambuddy_mobile/core/api/media_auth.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:bambuddy_mobile/features/common/media_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// The one place a media credential reaches an image, so the two ways it can
/// travel are asserted here rather than once per tile.
void main() {
  /// The `NetworkImage` the tile ended up with, unwrapped from the
  /// `ResizeImage` the decode cap puts around it.
  NetworkImage source(WidgetTester tester) {
    final image = tester.widget<Image>(find.byType(Image));
    final provider = image.image;
    return (provider is ResizeImage ? provider.imageProvider : provider)
        as NetworkImage;
  }

  Future<void> pump(
    WidgetTester tester, {
    required Override auth,
    Override? profile,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [profile ?? fakeServerProfileOverride(), auth],
        child: plApp(
          MediaImage(
            path: '/api/v1/archives/7/thumbnail',
            width: 52,
            height: 52,
            placeholder: (status) => Text('placeholder:${status.name}'),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a token session signs the URL and sends no headers', (
    tester,
  ) async {
    await pump(tester, auth: mediaAuthOverride());

    expect(
      source(tester).url,
      '$fakeServerBaseUrl/api/v1/archives/7/thumbnail?token=tok',
    );
    expect(source(tester).headers, anyOf(isNull, isEmpty));
  });

  testWidgets('an API-key session sends the header and leaves the URL bare', (
    tester,
  ) async {
    // The server refuses a media token minted by an API key, so the credential
    // has nowhere to go but a header — and the URL must stay clean, or the
    // stale-token branch on the server rejects the request before the header
    // is ever read.
    await pump(
      tester,
      auth: mediaAuthProvider.overrideWith(
        (ref) async => const MediaAuth(headers: {'X-API-Key': 'bb_key'}),
      ),
    );

    expect(
      source(tester).url,
      '$fakeServerBaseUrl/api/v1/archives/7/thumbnail',
    );
    expect(source(tester).headers, {'X-API-Key': 'bb_key'});
  });

  testWidgets('a path that already has a query keeps it', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [fakeServerProfileOverride(), mediaAuthOverride()],
        child: plApp(
          MediaImage(
            path: '/api/v1/printers/1/cover?view=top',
            placeholder: (_) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      source(tester).url,
      '$fakeServerBaseUrl/api/v1/printers/1/cover?view=top&token=tok',
    );
  });

  testWidgets('no server profile is unavailable, never a spinner that spins '
      'for good', (tester) async {
    await pump(
      tester,
      auth: mediaAuthOverride(),
      profile: noServerProfileOverride,
    );

    expect(find.text('placeholder:unavailable'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('a credential that will not mint reads as unauthenticated', (
    tester,
  ) async {
    await pump(
      tester,
      auth: mediaAuthProvider.overrideWith(
        (ref) async => throw Exception('no mint'),
      ),
    );
    await tester.pump();

    expect(find.text('placeholder:unauthenticated'), findsOneWidget);
  });

  testWidgets('a bounded box caps the decode width and not the height', (
    tester,
  ) async {
    // Capping both makes ResizeImage decode to exactly the box, which stretches
    // a render of another shape instead of letting BoxFit.cover crop it.
    await pump(tester, auth: mediaAuthOverride());

    final resize =
        tester.widget<Image>(find.byType(Image)).image as ResizeImage;
    expect(resize.width, isNotNull);
    expect(resize.height, isNull);
  });

  testWidgets(
    'zoom widens the decode, so the cropped-in part keeps its pixels',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [fakeServerProfileOverride(), mediaAuthOverride()],
          child: plApp(
            MediaImage(
              path: '/api/v1/archives/7/thumbnail',
              width: 50,
              height: 50,
              zoom: 2,
              placeholder: (_) => const SizedBox.shrink(),
            ),
          ),
        ),
      );
      await tester.pump();

      final resize =
          tester.widget<Image>(find.byType(Image)).image as ResizeImage;
      final dpr = tester.view.devicePixelRatio;
      expect(resize.width, (50 * 2 * dpr).round());
    },
  );

  testWidgets('an unbounded box caps no decode resolution', (tester) async {
    // `cacheWidth` is computed from the box; a photo told to fill the screen
    // has no width to compute from, and `double.infinity` would round to a
    // nonsense target.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [fakeServerProfileOverride(), mediaAuthOverride()],
        child: plApp(
          MediaImage(
            path: '/api/v1/archives/7/photos/finish.jpg',
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.contain,
            placeholder: (_) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.widget<Image>(find.byType(Image)).image, isA<NetworkImage>());
  });
}
