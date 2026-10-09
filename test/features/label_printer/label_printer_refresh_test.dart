import 'package:bambuddy_mobile/core/network/label_printer_discovery.dart';
import 'package:bambuddy_mobile/data/label_printer_repository.dart';
import 'package:bambuddy_mobile/features/label_printer/label_printer_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:bambuddy_mobile/core/models/label_printer.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Answering extends LabelPrinterRepository {
  _Answering(this.up) : super(Dio());
  final bool up;

  @override
  Future<LabelPrinterInfo?> info() async => up
      ? const LabelPrinterInfo(
          model: 'QL-600',
          connected: true,
          labelId: '62x29',
          maxCopies: 50,
        )
      : null;
}

void main() {
  const old = 'http://10.0.0.5:8000';

  Future<ProviderContainer> container({
    Map<String, Object> stored = const {},
    bool up = false,
  }) async {
    SharedPreferences.setMockInitialValues({
      'label_printer_url': old,
      ...stored,
    });
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        labelPrinterRepositoryProvider.overrideWith((ref) => _Answering(up)),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Stream<List<DiscoveredLabelPrinter>> found(List<(String, String)> printers) =>
      Stream.value([
        for (final (name, url) in printers)
          DiscoveredLabelPrinter(name: name, baseUrl: url),
      ]);

  test('takes the new address of a server found by name', () async {
    final c = await container(stored: {'label_printer_name': 'rpi'});
    await c
        .read(labelPrinterUrlProvider.notifier)
        .refresh(
          discover: () => found([
            ('other', 'http://10.0.0.9:8000'),
            ('rpi', 'http://10.0.0.7:8000'),
          ]),
        );
    expect(c.read(labelPrinterUrlProvider), 'http://10.0.0.7:8000');
    expect(c.read(settingsRepositoryProvider).loadLabelPrinterName(), 'rpi');
  });

  test('does not search while the saved address still answers', () async {
    final c = await container(stored: {'label_printer_name': 'rpi'}, up: true);
    await c
        .read(labelPrinterUrlProvider.notifier)
        .refresh(discover: () => throw StateError('must not search'));
    expect(c.read(labelPrinterUrlProvider), old);
  });

  test('an address typed by hand is never replaced', () async {
    final c = await container();
    await c
        .read(labelPrinterUrlProvider.notifier)
        .refresh(discover: () => throw StateError('must not search'));
    expect(c.read(labelPrinterUrlProvider), old);
  });

  test(
    'keeps the address when the server is not found or search fails',
    () async {
      final c = await container(stored: {'label_printer_name': 'rpi'});
      final notifier = c.read(labelPrinterUrlProvider.notifier);
      await notifier.refresh(discover: () => found([('other', 'http://x:1')]));
      await notifier.refresh(
        discover: () => Stream.error(StateError('no mdns')),
      );
      expect(c.read(labelPrinterUrlProvider), old);
    },
  );
}
