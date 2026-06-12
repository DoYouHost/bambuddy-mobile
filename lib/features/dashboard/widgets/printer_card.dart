import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/printer_status.dart';
import '../../../data/printers_repository.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers.dart';
import '../../camera/camera_view.dart';
import '../controls_providers.dart';

class PrinterCard extends StatefulWidget {
  const PrinterCard({super.key, required this.item});

  final PrinterWithStatus item;

  @override
  State<PrinterCard> createState() => _PrinterCardState();
}

class _PrinterCardState extends State<PrinterCard> {
  /// Rozwinięcie sekcji szczegółów (AMS, szpula, łączność). Trzymane lokalnie,
  /// więc przeżywa odświeżenia z pollingu/WS (karta ma klucz po id drukarki).
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final status = widget.item.status;
    final connected = status?.connected ?? false;
    final printing = status?.isPrinting ?? false;
    final readings = _buildReadings(status?.temperatures);
    final hasDetails = status?.hasDetails ?? false;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.print,
                  color: connected
                      ? theme.colorScheme.primary
                      : theme.disabledColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.item.printer.name,
                    style: theme.textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Podgląd kamery — tylko gdy drukarka jest połączona (offline
                // i tak nie zwróci strumienia).
                if (connected)
                  IconButton(
                    tooltip: l10n.cameraTooltip,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.videocam_outlined),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => CameraView(
                          printerId: widget.item.printer.id,
                          printerName: widget.item.printer.name,
                        ),
                      ),
                    ),
                  ),
                _StateChip(
                  label: status == null
                      ? l10n.statusUnavailable
                      : (status.state ??
                          (connected ? l10n.online : l10n.offline)),
                  connected: connected,
                  active: printing,
                ),
              ],
            ),
            if (printing) ...[
              const SizedBox(height: 10),
              _PrintPanel(status: status!),
            ],
            if (readings.isNotEmpty) ...[
              const SizedBox(height: 10),
              _TempGrid(readings: readings),
            ],
            if (status != null) ...[
              _ControlsActions(
                printerId: widget.item.printer.id,
                status: status,
              ),
              _ControlsRow(status: status),
            ],
            if (hasDetails) ...[
              const SizedBox(height: 6),
              _DetailsToggle(
                expanded: _expanded,
                onTap: () => setState(() => _expanded = !_expanded),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: _expanded
                    ? _DetailsPanel(status: status!)
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Klikalny pasek „Szczegóły ▾" rozwijający sekcję AMS/łączności.
class _DetailsToggle extends StatelessWidget {
  const _DetailsToggle({required this.expanded, required this.onTap});

  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final scheme = theme.colorScheme;
    final color = scheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Ink(
        decoration: BoxDecoration(
          // Delikatne odróżnienie od tła karty — ten sam ton co kafelki/chipy.
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              expanded ? l10n.detailsHide : l10n.detailsShow,
              style: theme.textTheme.labelLarge?.copyWith(color: color),
            ),
            const SizedBox(width: 4),
            AnimatedRotation(
              turns: expanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 200),
              child: Icon(Icons.expand_more, size: 20, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rozwinięta sekcja szczegółów: jednostki AMS z kolorowymi slotami,
/// szpula zewnętrzna oraz metadane łączności (model, Wi-Fi, drzwiczki).
class _DetailsPanel extends StatelessWidget {
  const _DetailsPanel({required this.status});

  final PrinterStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ams = status.ams ?? const [];
    final spools = status.externalSpools;
    // Materiał faktycznie załadowany (na aktywnym ekstruderze) — to JEGO
    // podświetlamy, niezależnie od kolejności na liście.
    final active = status.activeTray;
    final dual = status.isDualExtruder;
    final activeExtruder = status.activeExtruder;

    final sections = <Widget>[
      for (var i = 0; i < ams.length; i++)
        _AmsUnitView(
          unit: ams[i],
          unitIndex: i,
          active: active,
          // Na dwudyszowej pokazujemy, który ekstruder karmi ta jednostka.
          extruder: dual ? (status.amsExtruderMap?[ams[i].id]) : null,
          activeExtruder: activeExtruder,
        ),
      if (spools.isNotEmpty)
        _TraySection(
          title: l10n.externalSpool,
          trays: spools,
          active: active,
          // Szpula→ekstruder liczona z id (odwrotnie do kolejności: 254→lewy).
          extruderOf:
              dual ? (i) => status.extruderForExternal(spools[i].id) : (_) => null,
          activeExtruder: activeExtruder,
        ),
    ];

    final info = _InfoRow(status: status);

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final s in sections) ...[s, const SizedBox(height: 10)],
          info,
        ],
      ),
    );
  }
}

/// Jedna jednostka AMS: nagłówek (numer + ekstruder + wilgotność + temperatura)
/// i sloty. [active] to instancja faktycznie załadowanego slotu (z modelu) —
/// porównujemy przez tożsamość, więc podświetla się dokładnie ten jeden.
class _AmsUnitView extends StatelessWidget {
  const _AmsUnitView({
    required this.unit,
    required this.unitIndex,
    required this.active,
    required this.extruder,
    required this.activeExtruder,
  });

  final AmsUnit unit;
  final int unitIndex;
  final AmsTray? active;
  final int? extruder;
  final int? activeExtruder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    final trays = unit.trays ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l10n.amsUnit(unitIndex + 1),
              style: theme.textTheme.labelLarge,
            ),
            if (extruder != null) ...[
              const SizedBox(width: 6),
              _ExtruderBadge(
                extruder: extruder!,
                active: extruder == activeExtruder,
              ),
            ],
            const Spacer(),
            if (unit.humidity != null)
              _MetaItem(
                icon: Icons.water_drop_outlined,
                text: '${unit.humidity}%',
              ),
            if (unit.humidity != null && unit.temp != null)
              const SizedBox(width: 12),
            if (unit.temp != null)
              _MetaItem(
                icon: Icons.thermostat,
                text: '${unit.temp!.toStringAsFixed(0)}°',
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in trays)
              _TrayChip(tray: t, active: identical(t, active)),
          ],
        ),
        if (trays.isEmpty)
          Text('—', style: theme.textTheme.bodySmall?.copyWith(color: color)),
      ],
    );
  }
}

/// Sekcja slotów z tytułem (np. szpula zewnętrzna). [extruderOf] mapuje indeks
/// na ekstruder (na dwudyszowej), [active] to faktycznie załadowany slot.
class _TraySection extends StatelessWidget {
  const _TraySection({
    required this.title,
    required this.trays,
    required this.active,
    required this.extruderOf,
    required this.activeExtruder,
  });

  final String title;
  final List<AmsTray> trays;
  final AmsTray? active;
  final int? Function(int index) extruderOf;
  final int? activeExtruder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < trays.length; i++)
              _TrayChip(
                tray: trays[i],
                active: identical(trays[i], active),
                extruder: extruderOf(i),
                activeExtruder: activeExtruder,
                // Szpula zewnętrzna: drukarka nie mierzy zapełnienia (brak RFID
                // jak w oryginalnych filamentach Bambu w AMS) — nie pokazujemy %.
                allowRemain: false,
              ),
          ],
        ),
      ],
    );
  }
}

/// Chip pojedynczego slotu: opcjonalny znacznik ekstrudera + kropka w kolorze
/// filamentu + materiał + ilość. Aktywny (załadowany) slot dostaje obwódkę.
class _TrayChip extends StatelessWidget {
  const _TrayChip({
    required this.tray,
    required this.active,
    this.extruder,
    this.activeExtruder,
    this.allowRemain = true,
  });

  final AmsTray tray;
  final bool active;
  final int? extruder;
  final int? activeExtruder;

  /// Czy w ogóle pokazywać % zapełnienia (tylko AMS — szpula zewnętrzna nie ma
  /// wiarygodnego pomiaru).
  final bool allowRemain;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final empty = tray.isEmpty;
    final dotColor = empty ? null : _parseTrayColor(tray.trayColor);

    final label = empty
        ? l10n.traySlotEmpty
        : (tray.materialLabel ?? l10n.traySlotEmpty);
    final remain = tray.remain;
    final showRemain = allowRemain && !empty && remain != null && remain >= 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        border: active
            ? Border.all(color: scheme.primary, width: 1.5)
            : Border.all(color: Colors.transparent, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (extruder != null) ...[
            _ExtruderBadge(
              extruder: extruder!,
              active: extruder == activeExtruder,
            ),
            const SizedBox(width: 6),
          ],
          _ColorDot(color: dotColor),
          const SizedBox(width: 6),
          Text(
            showRemain ? '$label · $remain%' : label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: empty ? scheme.onSurfaceVariant : scheme.onSurface,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Mały znacznik ekstrudera dla maszyn dwudyszowych: ikona + strona
/// (L/P — lewy/prawy). Mapowanie wg kontraktu: ekstruder 1 = lewy, 0 = prawy
/// (potwierdzone na żywo: AMS → ekstruder 1 = lewy). Aktywny ekstruder w
/// kolorze akcentu, pozostałe przygaszone.
class _ExtruderBadge extends StatelessWidget {
  const _ExtruderBadge({required this.extruder, required this.active});

  final int extruder;
  final bool active;

  bool get _isLeft => extruder == 1;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final color = active ? scheme.primary : scheme.onSurfaceVariant;
    final short = _isLeft ? l10n.extruderLeftShort : l10n.extruderRightShort;
    return Tooltip(
      message: _isLeft ? l10n.extruderLeft : l10n.extruderRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.print_outlined, size: 13, color: color),
          const SizedBox(width: 2),
          Text(
            short,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Kółko w kolorze filamentu; pusty/nieznany slot → przekreślona obwódka.
class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (color == null) {
      return Icon(Icons.circle_outlined, size: 14, color: scheme.outline);
    }
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: scheme.outlineVariant, width: 0.5),
      ),
    );
  }
}

/// Wiersz metadanych łączności: model, sygnał Wi-Fi, stan drzwiczek.
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.status});

  final PrinterStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final items = <Widget>[
      if (status.model != null)
        _MetaItem(icon: Icons.precision_manufacturing, text: status.model!),
      if (status.wifiSignal != null)
        _MetaItem(icon: Icons.wifi, text: '${status.wifiSignal} dBm'),
      if (status.doorOpen != null)
        _MetaItem(
          icon: status.doorOpen!
              ? Icons.meeting_room
              : Icons.meeting_room_outlined,
          text: status.doorOpen! ? l10n.doorOpen : l10n.doorClosed,
        ),
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 14, runSpacing: 4, children: items);
  }
}

/// Parsuje kolor filamentu z hex RRGGBBAA na [Color]; null gdy niepoprawny.
Color? _parseTrayColor(String? hex) {
  if (hex == null || hex.length != 8) return null;
  final rgb = int.tryParse(hex.substring(0, 6), radix: 16);
  final a = int.tryParse(hex.substring(6, 8), radix: 16);
  if (rgb == null || a == null) return null;
  return Color((a << 24) | rgb);
}

/// Panel aktywnego wydruku: nazwa, pasek postępu z %, ETA i warstwy.
class _PrintPanel extends StatelessWidget {
  const _PrintPanel({required this.status});

  final PrinterStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final progress = status.progress;
    final name = status.currentPrint ?? status.gcodeFile;

    final remaining = status.remainingTime;
    final meta = <Widget>[
      if (remaining != null && remaining > 0)
        _MetaItem(
          icon: Icons.schedule,
          text: l10n.remaining(_durationText(l10n, remaining)),
        ),
      if (remaining != null && remaining > 0)
        _MetaItem(
          icon: Icons.flag_outlined,
          text: l10n.eta(_etaTime(remaining)),
        ),
      if (status.layerNum != null && status.totalLayers != null)
        _MetaItem(
          icon: Icons.layers_outlined,
          text: '${status.layerNum}/${status.totalLayers}',
        ),
    ];

    // Faza przygotowania (nagrzewanie, auto bed leveling): pokaż nazwę
    // etapu i nieoznaczony pasek zamiast mylącego 0%.
    final stage = status.stgCurName?.trim();
    final showStage = status.isPreparing && stage != null && stage.isNotEmpty;

    // Rząd 1: nazwa pliku + (w przygotowaniu) nazwa etapu.
    final nameBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (name != null)
          Text(
            name,
            style: theme.textTheme.bodyMedium,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        if (showStage) ...[
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.autorenew, size: 14, color: scheme.primary),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  stage,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.primary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ],
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Rząd 1: miniatura + nazwa pliku.
          Row(
            children: [
              if (status.coverUrl != null) ...[
                _CoverThumbnail(coverUrl: status.coverUrl!),
                const SizedBox(width: 12),
              ],
              Expanded(child: nameBlock),
            ],
          ),
          const SizedBox(height: 10),
          // Rząd 2: pasek postępu + reszta — pełna szerokość, od lewej krawędzi.
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    // Faza przygotowania → nieoznaczony pasek (bez 0%).
                    value: showStage
                        ? null
                        : (progress == null
                            ? null
                            : (progress / 100).clamp(0.0, 1.0)),
                    minHeight: 6,
                  ),
                ),
              ),
              if (progress != null && !showStage) ...[
                const SizedBox(width: 10),
                Text(
                  '${progress.toStringAsFixed(0)}%',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ],
          ),
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 14, runSpacing: 4, children: meta),
          ],
        ],
      ),
    );
  }
}

class _MetaItem extends StatelessWidget {
  const _MetaItem({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(text, style: theme.textTheme.bodySmall?.copyWith(color: color)),
      ],
    );
  }
}

/// Miniatura okładki bieżącego wydruku. Pobiera obrazek z `cover_url`
/// dołączając token strumienia kamery (`?token=`). Placeholder zamiast
/// błędu — nigdy nie wywraca karty.
///
/// M2: proaktywne odświeżanie tokenu i reaktywna invalidacja po 401
/// (`ref.invalidate(cameraTokenProvider)`) wejdą razem z podglądem kamery.
class _CoverThumbnail extends ConsumerWidget {
  const _CoverThumbnail({required this.coverUrl});

  final String coverUrl;

  static const _size = 64.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    Widget placeholder([IconData icon = Icons.image_outlined]) => Container(
          width: _size,
          height: _size,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: scheme.onSurfaceVariant, size: 22),
        );

    final baseUrl = ref.watch(serverProfileProvider)?.baseUrl;
    if (baseUrl == null) return placeholder();

    return ref.watch(cameraTokenProvider).when(
          loading: placeholder,
          error: (_, _) => placeholder(Icons.broken_image_outlined),
          data: (token) => ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(
              '$baseUrl$coverUrl?token=$token',
              width: _size,
              height: _size,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) =>
                  placeholder(Icons.broken_image_outlined),
              loadingBuilder: (_, child, progress) =>
                  progress == null ? child : placeholder(),
            ),
          ),
        );
  }
}

/// Siatka kafelków temperatur (2 w rzędzie), każdy z ikoną i parą
/// wartość aktualna / docelowa.
class _TempGrid extends StatelessWidget {
  const _TempGrid({required this.readings});

  final List<_TempReading> readings;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 8.0;
        final tileWidth = (constraints.maxWidth - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final r in readings)
              SizedBox(width: tileWidth, child: _TempTile(reading: r)),
          ],
        );
      },
    );
  }
}

/// Interaktywny pasek sterowania (M4): pauza/wznów/stop (stop zawsze za
/// dialogiem potwierdzenia), światło komory i prędkość. Stan optymistyczny +
/// rollback trzyma [controlsProvider]; tu tylko render, wysłanie akcji i
/// SnackBar z wynikiem. Chowa się gdy drukarka odłączona.
class _ControlsActions extends ConsumerWidget {
  const _ControlsActions({required this.printerId, required this.status});

  final int printerId;
  final PrinterStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final connected = status.connected ?? false;
    if (!connected) return const SizedBox.shrink();

    final forbidden = ref.watch(controlsProvider.select((s) => s.forbidden));
    if (forbidden) {
      // Klucz API bez `can_control_printer` — zamiast martwych przycisków
      // pokazujemy czytelny powód.
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          children: [
            Icon(Icons.lock_outline,
                size: 16, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                l10n.ctrlForbidden,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );
    }

    final pending =
        ref.watch(controlsProvider.select((s) => s.pendingFor(printerId)));
    final light = pending.light ?? status.chamberLight ?? false;
    final speedLevel = pending.speedLevel ?? status.speedLevel;

    final printing = status.isPrinting;
    final paused = status.isPaused;
    final activePrint = printing && !paused;

    final buttons = <Widget>[
      if (activePrint)
        _LifecycleButton(
          icon: Icons.pause,
          label: l10n.ctrlPause,
          busy: pending.isBusy(ControlAction.pause),
          onPressed: () => _run(context, ref, ControlAction.pause),
        ),
      if (paused)
        _LifecycleButton(
          icon: Icons.play_arrow,
          label: l10n.ctrlResume,
          busy: pending.isBusy(ControlAction.resume),
          onPressed: () => _run(context, ref, ControlAction.resume),
        ),
      if (printing)
        _LifecycleButton(
          icon: Icons.stop,
          label: l10n.ctrlStop,
          danger: true,
          busy: pending.isBusy(ControlAction.stop),
          onPressed: () => _confirmStop(context, ref),
        ),
      _LightToggle(
        on: light,
        busy: pending.isBusy(ControlAction.light),
        onPressed: () => _toggleLight(context, ref, on: !light),
      ),
      if (printing)
        _SpeedControl(
          level: speedLevel,
          busy: pending.isBusy(ControlAction.speed),
          onSelected: (mode) => _setSpeed(context, ref, mode),
        ),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(spacing: 8, runSpacing: 8, children: buttons),
    );
  }

  Future<void> _run(
      BuildContext context, WidgetRef ref, ControlAction action) async {
    final notifier = ref.read(controlsProvider.notifier);
    final result = switch (action) {
      ControlAction.pause => await notifier.pause(printerId),
      ControlAction.resume => await notifier.resume(printerId),
      ControlAction.stop => await notifier.stop(printerId),
      _ => ControlResult.ok,
    };
    if (context.mounted) _showResult(context, result);
  }

  Future<void> _toggleLight(BuildContext context, WidgetRef ref,
      {required bool on}) async {
    final result =
        await ref.read(controlsProvider.notifier).setLight(printerId, on: on);
    if (context.mounted) _showResult(context, result);
  }

  Future<void> _setSpeed(
      BuildContext context, WidgetRef ref, int mode) async {
    final result =
        await ref.read(controlsProvider.notifier).setSpeed(printerId, mode);
    if (context.mounted) _showResult(context, result);
  }

  /// Stop ZAWSZE za potwierdzeniem — to deliverable, nie szlif: łatwo ubić
  /// wielogodzinny wydruk jednym tapnięciem.
  Future<void> _confirmStop(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.ctrlStopConfirmTitle),
        content: Text(l10n.ctrlStopConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.ctrlStop),
          ),
        ],
      ),
    );
    if ((confirmed ?? false) && context.mounted) {
      await _run(context, ref, ControlAction.stop);
    }
  }

  void _showResult(BuildContext context, ControlResult result) {
    final l10n = AppLocalizations.of(context);
    final msg = switch (result) {
      ControlResult.ok => null,
      ControlResult.forbidden => l10n.ctrlForbidden,
      ControlResult.error => l10n.ctrlFailed,
    };
    if (msg == null) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }
}

const _btnSpinner = SizedBox(
  width: 16,
  height: 16,
  child: CircularProgressIndicator(strokeWidth: 2),
);

/// Przycisk akcji cyklu życia wydruku (pauza/wznów/stop). W locie pokazuje
/// spinner i jest zablokowany; `danger` koloruje stop na czerwono.
class _LifecycleButton extends StatelessWidget {
  const _LifecycleButton({
    required this.icon,
    required this.label,
    required this.busy,
    required this.onPressed,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final bool busy;
  final VoidCallback onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = danger ? scheme.error : null;
    return OutlinedButton.icon(
      onPressed: busy ? null : onPressed,
      icon: busy ? _btnSpinner : Icon(icon, size: 18, color: fg),
      label: Text(label, style: fg == null ? null : TextStyle(color: fg)),
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        side: danger
            ? BorderSide(color: scheme.error.withValues(alpha: 0.5))
            : null,
      ),
    );
  }
}

/// Przełącznik światła komory. Pokazuje aktualny (optymistyczny) stan;
/// żółta żarówka = włączone.
class _LightToggle extends StatelessWidget {
  const _LightToggle({
    required this.on,
    required this.busy,
    required this.onPressed,
  });

  final bool on;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    const amber = Color(0xFFFFC107);
    return OutlinedButton.icon(
      onPressed: busy ? null : onPressed,
      icon: busy
          ? _btnSpinner
          : Icon(on ? Icons.lightbulb : Icons.lightbulb_outline,
              size: 18, color: on ? amber : null),
      label: Text(on ? l10n.ctrlLightOn : l10n.ctrlLightOff),
      style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
    );
  }
}

/// Wybór prędkości druku (1–4). Tapnięcie otwiera menu z czterema poziomami;
/// bieżący jest odhaczony. W locie zablokowany ze spinnerem.
class _SpeedControl extends StatelessWidget {
  const _SpeedControl({
    required this.level,
    required this.busy,
    required this.onSelected,
  });

  final int? level;
  final bool busy;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final label = _speedName(l10n, level) ?? l10n.ctrlSpeed;

    return PopupMenuButton<int>(
      enabled: !busy,
      tooltip: l10n.ctrlSpeed,
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (var m = 1; m <= 4; m++)
          CheckedPopupMenuItem<int>(
            value: m,
            checked: level == m,
            child: Text(_speedName(l10n, m)!),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: scheme.outline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            busy
                ? _btnSpinner
                : Icon(Icons.speed, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Text(label, style: theme.textTheme.labelLarge),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down,
                size: 18, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

String? _speedName(AppLocalizations l10n, int? level) => switch (level) {
      1 => l10n.speedSilent,
      2 => l10n.speedStandard,
      3 => l10n.speedSport,
      4 => l10n.speedLudicrous,
      _ => null,
    };

/// Pasek read-only chipów ze stanem czujników (wentylatory, nawiew komory).
/// Sterowalne wartości (światło, prędkość) są w [_ControlsActions].
/// Renderuje się tylko gdy serwer poda którąkolwiek wartość.
class _ControlsRow extends StatelessWidget {
  const _ControlsRow({required this.status});

  final PrinterStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final fanColor = _fanColor(context);

    // `valueAlternatives` rezerwuje szerokość na najszerszą możliwą wartość,
    // żeby chip nie zmieniał rozmiaru przy pollingu (np. 53% → 100%).
    // Wentylatory 0–100%, prędkość do 166% (Ludicrous) → 3 cyfry.
    final chips = <Widget>[
      if (status.coolingFanSpeed != null)
        _ControlChip(
          icon: Icons.air,
          label: l10n.ctrlFanPart,
          value: '${status.coolingFanSpeed}%',
          valueAlternatives: const ['100%'],
          color: fanColor(status.coolingFanSpeed!),
        ),
      if (status.bigFan1Speed != null)
        _ControlChip(
          icon: Icons.cyclone,
          label: l10n.ctrlFanAux,
          value: '${status.bigFan1Speed}%',
          valueAlternatives: const ['100%'],
          color: fanColor(status.bigFan1Speed!),
        ),
      if (status.bigFan2Speed != null)
        _ControlChip(
          icon: Icons.wind_power,
          label: l10n.ctrlFanChamber,
          value: '${status.bigFan2Speed}%',
          valueAlternatives: const ['100%'],
          color: fanColor(status.bigFan2Speed!),
        ),
      if (status.airductIsHeating != null)
        _ControlChip(
          icon: status.airductIsHeating!
              ? Icons.local_fire_department
              : Icons.ac_unit,
          label: l10n.ctrlAirduct,
          value: status.airductIsHeating!
              ? l10n.ctrlAirductHeating
              : l10n.ctrlAirductCooling,
          valueAlternatives: [l10n.ctrlAirductCooling, l10n.ctrlAirductHeating],
          color: status.airductIsHeating!
              ? const Color(0xFFFF8A50)
              : const Color(0xFF4FC3F7),
        ),
    ];

    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(spacing: 8, runSpacing: 8, children: chips),
    );
  }

  // Wentylator: stojący (0%) przygaszony, kręcący się — chłodny akcent.
  Color Function(int) _fanColor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return (speed) =>
        speed > 0 ? const Color(0xFF4FC3F7) : scheme.onSurfaceVariant;
  }
}

/// Pojedynczy chip sterowania: ikona + etykieta (mała) + wartość.
class _ControlChip extends StatelessWidget {
  const _ControlChip({
    required this.icon,
    required this.label,
    required this.value,
    this.valueAlternatives = const [],
    this.color,
  });

  final IconData icon;
  final String label;
  final String value;

  /// Wszystkie wartości, jakie ten chip może pokazać. Slot wartości
  /// rezerwuje szerokość na najszerszą z nich, więc chip ma stały rozmiar
  /// niezależnie od bieżącej wartości (np. „53%" vs „100%").
  final List<String> valueAlternatives;

  /// Akcent ikony/wartości; null = neutralny kolor z motywu.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = color ?? scheme.onSurfaceVariant;
    // Tabular figures: każda cyfra tej samej szerokości — brak drgania
    // przy zmianie cyfr o tej samej długości (np. 53% → 67%).
    final valueStyle = (theme.textTheme.labelMedium ?? const TextStyle())
        .copyWith(
      color: accent,
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    // Szerokość slotu = najszersza z możliwych wartości (zmierzona, nie
    // zgadnięta) → chip ma stały rozmiar mimo zmian wartości przy pollingu.
    // Pomiar uwzględnia skalowanie tekstu z MediaQuery.
    final scaler = MediaQuery.textScalerOf(context);
    final dir = Directionality.of(context);
    var slotWidth = 0.0;
    for (final v in [value, ...valueAlternatives]) {
      final tp = TextPainter(
        text: TextSpan(text: v, style: valueStyle),
        textDirection: dir,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      if (tp.width > slotWidth) slotWidth = tp.width;
    }

    return Tooltip(
      message: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: accent),
            const SizedBox(width: 6),
            SizedBox(
              width: slotWidth.ceilToDouble(),
              child: Text(value, style: valueStyle, maxLines: 1),
            ),
          ],
        ),
      ),
    );
  }
}

class _TempTile extends StatelessWidget {
  const _TempTile({required this.reading});

  final _TempReading reading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final actual = reading.actual;
    final target = reading.target;

    final iconColor = _tempIconColor(scheme, actual, target);
    // Cel pokazujemy tylko gdy ustawiony (>0); 0 = grzanie wyłączone.
    final hasTarget = target != null && target > 0;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Ikona w lewym górnym rogu + etykieta czujnika.
          Row(
            children: [
              Icon(reading.icon, size: 16, color: iconColor),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  reading.label(l10n),
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Aktualna: duża, żywy kolor, przy lewej. Cel: mniejszy,
          // półprzezroczysty, dosunięty do prawej krawędzi.
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                actual == null ? '—' : '${actual.toStringAsFixed(0)}°',
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: iconColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (hasTarget) ...[
                const Spacer(),
                Text(
                  '${target.toStringAsFixed(0)}°',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: iconColor.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Kolor ikony kafelka temperatury zależny od stanu czujnika:
/// biała gdy cel nieustawiony, niebieska przy chłodzeniu (aktualna nad celem),
/// pomarańczowa przy rozgrzewaniu i utrzymywaniu wysokiej temperatury.
Color _tempIconColor(ColorScheme scheme, double? actual, double? target) {
  // Cel nieustawiony (null lub 0 = grzanie wyłączone) → neutralna biała.
  if (target == null || target <= 0) return scheme.onSurface;
  // Tolerancja, by drobne wahania przy celu nie migotały kolorem.
  const tolerance = 2.0;
  if (actual != null && actual > target + tolerance) {
    return const Color(0xFF4FC3F7); // chłodzenie — niebieska
  }
  return const Color(0xFFFF8A50); // rozgrzewanie / wysoka temp — pomarańczowa
}

class _StateChip extends StatelessWidget {
  const _StateChip({
    required this.label,
    required this.connected,
    this.active = false,
  });

  final String label;
  final bool connected;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Chip(
      visualDensity: VisualDensity.compact,
      backgroundColor: active
          ? scheme.primaryContainer
          : (connected
              ? scheme.secondaryContainer
              : scheme.surfaceContainerHighest),
      label: Text(label, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

enum _TempKind { nozzle, bed, chamber, unknown }

/// Para odczytów (aktualny + docelowy) jednego czujnika. Etykieta jest
/// tłumaczona dopiero przy renderowaniu (z [BuildContext]).
class _TempReading {
  const _TempReading({
    required this.kind,
    required this.raw,
    required this.actual,
    required this.target,
    this.index,
  });

  final _TempKind kind;
  final String raw; // surowy klucz — pokazywany dla nieznanego czujnika
  final int? index; // numer dyszy (np. 2) lub null
  final double? actual;
  final double? target;

  String label(AppLocalizations l10n) => switch (kind) {
        _TempKind.nozzle =>
          index == null ? l10n.tempNozzle : l10n.tempNozzleNumbered('$index'),
        _TempKind.bed => l10n.tempBed,
        _TempKind.chamber => l10n.tempChamber,
        _TempKind.unknown => raw,
      };

  IconData get icon => switch (kind) {
        _TempKind.nozzle => Icons.local_fire_department,
        _TempKind.bed => Icons.wb_iridescent,
        _TempKind.chamber => Icons.thermostat,
        _TempKind.unknown => Icons.device_thermostat,
      };
}

/// Grupuje surowe klucze temperatur w pary aktualna/docelowa i porządkuje
/// znane czujniki (dysza, stół, komora) przed nieznanymi.
List<_TempReading> _buildReadings(Map<String, double>? temps) {
  if (temps == null || temps.isEmpty) return const [];

  final actuals = <String, double>{};
  final targets = <String, double>{};
  for (final entry in temps.entries) {
    var base = entry.key;
    final isTarget = base.endsWith('_target');
    if (isTarget) base = base.substring(0, base.length - '_target'.length);
    if (base.endsWith('_temper')) {
      base = base.substring(0, base.length - '_temper'.length);
    }
    (isTarget ? targets : actuals)[base] = entry.value;
  }

  const orderHint = ['nozzle', 'bed', 'chamber'];
  int rank(String base) {
    final stem = RegExp(r'^([a-z]+)').firstMatch(base)?.group(1) ?? base;
    final i = orderHint.indexOf(stem);
    return i == -1 ? orderHint.length : i;
  }

  final bases = {...actuals.keys, ...targets.keys}.toList()
    ..sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : a.compareTo(b);
    });

  return [
    for (final base in bases)
      _readingFor(base, actuals[base], targets[base]),
  ];
}

_TempReading _readingFor(String base, double? actual, double? target) {
  final numbered = RegExp(r'^([a-z]+)_(\d+)$').firstMatch(base);
  final stem = numbered?.group(1) ?? base;
  final index = numbered == null ? null : int.tryParse(numbered.group(2)!);

  final kind = switch (stem) {
    'nozzle' => _TempKind.nozzle,
    'bed' => _TempKind.bed,
    'chamber' => _TempKind.chamber,
    _ => _TempKind.unknown,
  };

  return _TempReading(
    kind: kind,
    raw: base,
    index: kind == _TempKind.nozzle ? index : null,
    actual: actual,
    target: target,
  );
}

String _durationText(AppLocalizations l10n, int minutes) => minutes < 60
    ? l10n.durationMinutes(minutes)
    : l10n.durationHoursMinutes(minutes ~/ 60, minutes % 60);

/// Godzina zakończenia (ETA) jako HH:mm = teraz + pozostałe minuty.
String _etaTime(int remainingMinutes) {
  final eta = DateTime.now().add(Duration(minutes: remainingMinutes));
  final hh = eta.hour.toString().padLeft(2, '0');
  final mm = eta.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}
