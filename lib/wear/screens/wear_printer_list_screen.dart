import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../wear_providers.dart';
import '../wear_status.dart';
import 'wear_printer_control_screen.dart';

/// Printer picker (shown only when more than one printer). Tapping a row pushes
/// its control screen.
class WearPrinterListBody extends ConsumerWidget {
  const WearPrinterListBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fleet = ref.watch(wearFleetProvider);
    final printers = fleet.valueOrNull ?? const [];
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 20, 8, 28),
      children: [
        const Center(
          child: Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('Printers', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
        for (final p in printers)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: _PrinterRow(
              name: p.printer.name,
              state: wearStateOf(p.status),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => WearPrinterControlScreen(
                    printerId: p.printer.id,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PrinterRow extends StatelessWidget {
  const _PrinterRow({
    required this.name,
    required this.state,
    required this.onTap,
  });

  final String name;
  final WearState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration:
                      BoxDecoration(color: state.color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                      Text(state.label,
                          style: TextStyle(fontSize: 11, color: state.color)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 18),
              ],
            ),
          ),
        ),
      );
}
