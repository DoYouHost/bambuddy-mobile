import 'dart:async';

import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/label_printer.dart';
import '../../core/network/label_printer_discovery.dart';
import '../../core/theme/dash_theme.dart';
import '../../data/label_printer_repository.dart';
import '../../l10n/app_localizations.dart';
import '../common/inline_note.dart';
import '../common/settings_entry_tile.dart';
import '../common/settings_rows.dart';
import 'label_printer_providers.dart';

/// Where spool labels are printed: the user's own label print server, found on
/// the LAN or typed in. Nothing here touches the bambuddy server.
class LabelPrinterScreen extends ConsumerStatefulWidget {
  const LabelPrinterScreen({super.key});

  @override
  ConsumerState<LabelPrinterScreen> createState() => _LabelPrinterScreenState();
}

class _LabelPrinterScreenState extends ConsumerState<LabelPrinterScreen> {
  final _address = TextEditingController();
  StreamSubscription<List<DiscoveredLabelPrinter>>? _scan;
  List<DiscoveredLabelPrinter> _found = const [];
  bool _scanning = false;
  bool _discoveryFailed = false;
  bool _checking = false;
  bool _notAServer = false;

  @override
  void initState() {
    super.initState();
    _address.text = ref.read(labelPrinterUrlProvider) ?? '';
  }

  @override
  void dispose() {
    _scan?.cancel();
    _address.dispose();
    super.dispose();
  }

  void _search() {
    setState(() {
      _scanning = true;
      _discoveryFailed = false;
      _found = const [];
    });
    _scan?.cancel();
    _scan = ref
        .read(labelPrinterDiscoveryProvider)()
        .listen(
          (found) => setState(() => _found = found),
          onError: (Object _) => setState(() {
            _discoveryFailed = true;
            _scanning = false;
          }),
          onDone: () => setState(() => _scanning = false),
        );
  }

  /// Saves [raw] only if something there answers as a label print server — a
  /// typo kept silently would surface as a failed print much later.
  Future<void> _use(String raw, {String? name}) async {
    final url = normalizeLabelPrinterUrl(raw);
    if (url.isEmpty) return;
    setState(() {
      _checking = true;
      _notAServer = false;
    });
    final info = await LabelPrinterRepository(
      createLabelPrinterDio(url),
    ).info();
    if (!mounted) return;
    if (info == null) {
      setState(() {
        _checking = false;
        _notAServer = true;
      });
      return;
    }
    await ref.read(labelPrinterUrlProvider.notifier).set(url, name: name);
    if (!mounted) return;
    _address.text = url;
    setState(() => _checking = false);
  }

  Future<void> _remove() async {
    await ref.read(labelPrinterUrlProvider.notifier).set(null);
    if (!mounted) return;
    _address.clear();
    setState(() => _notAServer = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final saved = ref.watch(labelPrinterUrlProvider);

    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: dashAppBar(context, title: l10n.labelPrinterTitle),
        body: ListView(
          padding: withSystemNavInset(
            context,
            const EdgeInsets.fromLTRB(
              DashSpace.gutter,
              DashSpace.sm,
              DashSpace.gutter,
              DashSpace.xl,
            ),
          ),
          children: [
            Text(l10n.labelPrinterIntro, style: t.bodyPlain),
            const SizedBox(height: DashSpace.lg),
            SettingsCard(rows: [_status(context, saved)]),
            const SizedBox(height: DashSpace.xl),
            OutlinedButton.icon(
              onPressed: _scanning ? null : _search,
              icon: _scanning
                  ? const DashSpinner(size: 16)
                  : const Icon(Icons.search),
              label: Text(
                _scanning
                    ? l10n.labelPrinterSearching
                    : l10n.labelPrinterSearch,
              ),
            ).tagged('label_printer.search'),
            if (_discoveryFailed)
              InlineNote(l10n.labelPrinterDiscoveryFailed, urgent: true)
            else if (!_scanning && _found.isEmpty && _scan != null)
              InlineNote(l10n.labelPrinterNoneFound, icon: Icons.info_outline),
            for (final p in _found)
              SettingsEntryTile(
                icon: Icons.print_outlined,
                title: p.name,
                subtitle: p.baseUrl,
                onTap: _checking ? () {} : () => _use(p.baseUrl, name: p.name),
                id: 'label_printer.found',
              ),
            const SizedBox(height: DashSpace.xl),
            TextField(
              controller: _address,
              enabled: !_checking,
              autocorrect: false,
              keyboardType: TextInputType.url,
              style: t.bodyStrong,
              decoration: dashFieldDecoration(
                t,
                labelText: l10n.labelPrinterAddress,
                hintText: '192.168.1.40:$labelPrinterDefaultPort',
              ),
              onSubmitted: _use,
            ).tagged('label_printer.address'),
            InlineNote(l10n.labelPrinterVlanNote, icon: Icons.info_outline),
            if (_notAServer)
              InlineNote(l10n.labelPrinterNotAServer, urgent: true),
            const SizedBox(height: DashSpace.md),
            FilledButton(
              onPressed: _checking ? null : () => _use(_address.text),
              child: _checking
                  ? const DashSpinner(size: 16)
                  : Text(l10n.labelPrinterSave),
            ).tagged('label_printer.save'),
          ],
        ),
      ),
    );
  }

  /// The chosen server and what it answers right now.
  Widget _status(BuildContext context, String? saved) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    if (saved == null) {
      return ListTile(title: Text(l10n.labelPrinterNotSet, style: t.body));
    }
    final info = ref.watch(labelPrinterInfoProvider);
    final line = info.when(
      loading: () => '…',
      error: (_, _) => l10n.labelPrinterOffline,
      data: (i) => switch (i) {
        null => l10n.labelPrinterOffline,
        _ when i.connected == false => l10n.labelPrinterPrinterOff,
        _ => l10n.labelPrinterReady(i.model ?? '?', i.labelId ?? '?'),
      },
    );
    final stock = info.valueOrNull;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DashSpace.md,
        DashSpace.md,
        DashSpace.xs,
        DashSpace.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: DashSpace.xs),
                child: Icon(
                  Icons.print_outlined,
                  size: 20,
                  color: t.accentGreenInk,
                ),
              ),
              const SizedBox(width: DashSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(line, style: t.bodyBold),
                    const SizedBox(height: DashSpace.xs),
                    Text(saved, style: t.microSoft),
                  ],
                ),
              ),
              IconButton(
                onPressed: _remove,
                tooltip: l10n.labelPrinterRemove,
                icon: const Icon(Icons.delete_outline),
              ).tagged('label_printer.remove'),
            ],
          ),
          if (stock != null && !stock.takesAnySpoolLabel)
            Padding(
              padding: const EdgeInsets.only(right: DashSpace.md),
              child: InlineNote(
                l10n.labelPrinterWrongStock(stock.labelId ?? '?'),
              ),
            ),
        ],
      ),
    );
  }
}
