import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diagnostics/log_tag.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/models/discovery.dart';
import '../../core/models/printer_create.dart';
import '../../core/models/printer_diagnostic.dart';
import '../../core/theme/dash_text.dart';
import '../../core/theme/dash_theme.dart';
import '../../data/printers_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common/dash_input.dart';
import '../common/dash_progress.dart';
import '../common/dash_snack.dart';
import 'providers.dart';

/// Bambu Lab model options for the (optional) model dropdown, grouped by series
/// to mirror the web form. `value` is the code stored on the server; `label` is
/// what the user sees (e.g. X1C → "X1 Carbon"). Free-form on the server, but a
/// fixed list avoids typos.
const _modelGroups = <(String, List<(String, String)>)>[
  ('A1 Series', [('A1', 'A1'), ('A1 Mini', 'A1 Mini')]),
  ('A2 Series', [('A2L', 'A2L')]),
  (
    'H2 Series',
    [('H2C', 'H2C'), ('H2D', 'H2D'), ('H2D Pro', 'H2D Pro'), ('H2S', 'H2S')],
  ),
  ('P Series', [('P1P', 'P1P'), ('P1S', 'P1S'), ('P2S', 'P2S')]),
  ('X1 Series', [('X1', 'X1'), ('X1C', 'X1 Carbon'), ('X1E', 'X1E')]),
  ('X2 Series', [('X2D', 'X2D')]),
];

/// Sentinel value for the "Not set" model entry — DropdownMenu is driven with
/// non-null values only (a null-valued entry has edge cases), mapped back to a
/// null model on submit.
const _modelNone = '';

/// All known model codes (flat) — used to decide whether a discovered/prefilled
/// model matches an entry we can show in the dropdown.
Set<String> get _modelCodes => {
  for (final (_, models) in _modelGroups)
    for (final (v, _) in models) v,
};

/// Form to add a printer via `POST /printers/`. The server tests the connection
/// before saving, so a failure comes back inline. Also offers subnet discovery
/// (prefill from a found printer) and a pre-save connection diagnostic.
class AddPrinterScreen extends ConsumerStatefulWidget {
  const AddPrinterScreen({super.key});

  @override
  ConsumerState<AddPrinterScreen> createState() => _AddPrinterScreenState();
}

class _AddPrinterScreenState extends ConsumerState<AddPrinterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _ip = TextEditingController();
  final _serial = TextEditingController();
  final _accessCode = TextEditingController();
  final _location = TextEditingController();
  String _model = _modelNone;
  bool _obscureAccessCode = true;
  bool _autoArchive = true;
  bool _busy = false;
  String? _error;

  // Discovery (SSDP + subnet scan).
  DiscoveryInfo? _discovery;
  String? _subnet;
  final _customSubnet = TextEditingController();
  bool _useCustomSubnet = false;
  bool _scanning = false;
  bool _hasScanned = false;
  ScanStatus? _scanProgress;
  List<DiscoveredPrinter> _found = const [];
  String? _scanError;

  /// Sentinel value in the subnet dropdown that reveals the custom CIDR field.
  static const _customSubnetOption = '__custom__';

  /// Subnet scanning is used for Docker (no multicast) or a custom subnet on a
  /// different L3 segment; otherwise a native install uses SSDP discovery.
  bool get _wantsSubnetScan =>
      (_discovery?.isDocker ?? false) ||
      _useCustomSubnet ||
      (_discovery?.subnets.isEmpty ?? true);

  // Diagnostic.
  bool _diagnosing = false;
  PrinterDiagnosticResult? _diagnostic;
  String? _diagnosticError;

  @override
  void initState() {
    super.initState();
    _loadDiscoveryInfo();
  }

  @override
  void dispose() {
    _name.dispose();
    _ip.dispose();
    _serial.dispose();
    _accessCode.dispose();
    _location.dispose();
    _customSubnet.dispose();
    super.dispose();
  }

  /// Best-effort: if discovery isn't permitted (403) or fails, the scan section
  /// simply stays hidden.
  Future<void> _loadDiscoveryInfo() async {
    try {
      final info = await ref.read(discoveryRepositoryProvider).info();
      if (!mounted) return;
      setState(() {
        _discovery = info;
        _subnet = info.subnets.isNotEmpty ? info.subnets.first : null;
      });
    } on AppApiException {
      // No discovery available — leave the section hidden.
    }
  }

  Future<void> _scan() async {
    if (_scanning) return;
    // Custom subnet (or the no-detected-subnets fallback) reads the CIDR field;
    // otherwise the chosen detected subnet.
    final custom = _useCustomSubnet || (_discovery?.subnets.isEmpty ?? true);
    final cidr = custom ? _customSubnet.text.trim() : _subnet;
    if (_wantsSubnetScan && (cidr == null || cidr.isEmpty)) {
      setState(
        () => _scanError = AppLocalizations.of(context).addPrinterRequiredField,
      );
      return;
    }
    final repo = ref.read(discoveryRepositoryProvider);
    setState(() {
      _scanning = true;
      _hasScanned = false;
      _scanError = null;
      _found = const [];
      _scanProgress = null;
    });
    try {
      if (_wantsSubnetScan) {
        await repo.startScan(cidr!);
        // Poll progress + accumulate found printers until the scan stops (cap
        // the loop so a stuck backend can't spin forever).
        for (var i = 0; i < 300 && mounted; i++) {
          await Future<void>.delayed(const Duration(seconds: 1));
          if (!mounted) return;
          final status = await repo.scanStatus();
          final found = await repo.discoveredPrinters();
          if (!mounted) return;
          setState(() {
            _scanProgress = status;
            _found = found;
          });
          if (!status.running) break;
        }
      } else {
        // Native install: SSDP multicast for ~10 s, polling results as they land.
        await repo.startSsdp(duration: 10);
        for (var i = 0; i < 10 && mounted; i++) {
          await Future<void>.delayed(const Duration(seconds: 1));
          if (!mounted) return;
          final found = await repo.discoveredPrinters();
          if (mounted) setState(() => _found = found);
        }
        await repo.stopSsdp();
        if (mounted) {
          final found = await repo.discoveredPrinters();
          if (mounted) setState(() => _found = found);
        }
      }
    } on AppApiException {
      if (mounted) {
        setState(
          () => _scanError = AppLocalizations.of(context).addPrinterScanError,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _scanning = false;
          _hasScanned = true;
        });
      }
    }
  }

  void _applyDiscovered(DiscoveredPrinter p) {
    setState(() {
      if (p.name.isNotEmpty) _name.text = p.name;
      _ip.text = p.ipAddress;
      _serial.text = p.serial;
      final model = p.model;
      if (model != null && _modelCodes.contains(model)) _model = model;
    });
  }

  Future<void> _runDiagnostic() async {
    final l10n = AppLocalizations.of(context);
    final ip = _ip.text.trim();
    if (ip.isEmpty) {
      setState(() => _diagnosticError = l10n.addPrinterRequiredField);
      return;
    }
    setState(() {
      _diagnosing = true;
      _diagnostic = null;
      _diagnosticError = null;
    });
    try {
      final result = await ref
          .read(printersRepositoryProvider)
          .diagnose(
            ipAddress: ip,
            serialNumber: _serial.text.trim(),
            accessCode: _accessCode.text,
          );
      if (mounted) setState(() => _diagnostic = result);
    } on AuthException {
      if (mounted) {
        setState(() => _diagnosticError = l10n.addPrinterErrForbidden);
      }
    } on AppApiException {
      if (mounted) {
        setState(() => _diagnosticError = l10n.addPrinterDiagnosticError);
      }
    } finally {
      if (mounted) setState(() => _diagnosing = false);
    }
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(printersRepositoryProvider)
          .createPrinter(
            PrinterCreate(
              name: _name.text.trim(),
              serialNumber: _serial.text.trim(),
              ipAddress: _ip.text.trim(),
              accessCode: _accessCode.text,
              model: _model == _modelNone ? null : _model,
              location: _location.text.trim(),
              autoArchive: _autoArchive,
            ),
          );
      await ref.read(dashboardProvider.notifier).refresh();
      if (!mounted) return;
      messenger.snack(l10n.addPrinterSuccess);
      navigator.pop();
    } on CreatePrinterException catch (e) {
      if (!mounted) return;
      setState(() => _error = _failureText(l10n, e.reason));
    } on AuthException {
      if (!mounted) return;
      setState(() => _error = l10n.addPrinterErrForbidden);
    } on AppApiException {
      if (!mounted) return;
      setState(() => _error = l10n.addPrinterErrGeneric);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _failureText(AppLocalizations l10n, CreatePrinterFailure reason) =>
      switch (reason) {
        CreatePrinterFailure.connectionFailed => l10n.addPrinterErrConnection,
        CreatePrinterFailure.duplicateSerial => l10n.addPrinterErrDuplicate,
        CreatePrinterFailure.forbidden => l10n.addPrinterErrForbidden,
        CreatePrinterFailure.generic => l10n.addPrinterErrGeneric,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);

    String? required(String? v) =>
        (v == null || v.trim().isEmpty) ? l10n.addPrinterRequiredField : null;

    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: dashAppBar(context, title: l10n.addPrinterTitle),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: t.cardGradient,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: t.cardBorder),
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Only when the server supports discovery (info request
                    // succeeded — needs the DISCOVERY_SCAN permission).
                    if (_discovery != null) ...[
                      _scanSection(t, l10n),
                      const Divider(height: 32),
                    ],
                    _field(
                      t,
                      controller: _name,
                      label: l10n.addPrinterName,
                      validator: required,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    _field(
                      t,
                      controller: _ip,
                      label: l10n.addPrinterIp,
                      hint: '192.168.1.50',
                      keyboardType: TextInputType.url,
                      validator: required,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    _field(
                      t,
                      controller: _serial,
                      label: l10n.addPrinterSerial,
                      validator: required,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    _field(
                      t,
                      controller: _accessCode,
                      label: l10n.addPrinterAccessCode,
                      obscureText: _obscureAccessCode,
                      keyboardType: TextInputType.number,
                      validator: required,
                      suffixIcon: IconButton(
                        onPressed: () => setState(
                          () => _obscureAccessCode = !_obscureAccessCode,
                        ),
                        icon: Icon(
                          _obscureAccessCode
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: t.textSecondary,
                        ),
                      ).tagged('add_printer.reveal_access_code'),
                    ),
                    const SizedBox(height: 12),
                    _modelDropdown(t, l10n),
                    const SizedBox(height: 12),
                    _field(
                      t,
                      controller: _location,
                      label: l10n.addPrinterLocation,
                      hint: l10n.addPrinterLocationOptional,
                      textInputAction: TextInputAction.done,
                    ),
                    const SizedBox(height: 4),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _autoArchive,
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _autoArchive = v ?? true),
                      activeColor: t.accentGreen,
                      checkColor: const Color(0xFF0A0C08),
                      title: Text(
                        l10n.addPrinterAutoArchive,
                        style: t.bodyStrong,
                      ),
                    ).tagged('add_printer.auto_archive'),
                    const SizedBox(height: 4),
                    _diagnosticSection(t, l10n),
                    const SizedBox(height: 16),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          _error!,
                          style: t.body.copyWith(color: t.danger),
                        ),
                      ),
                    FilledButton(
                      style: dashPrimaryButtonStyle(t),
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const DashSpinner(size: 20)
                          : Text(l10n.addPrinterSubmit),
                    ).tagged('add_printer.submit'),
                    const SizedBox(height: 10),
                    Text(
                      l10n.addPrinterConnectionNote,
                      style: TextStyle(
                        fontFamily: DashTokens.fontUi,
                        fontSize: 12,
                        color: t.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- Scan section -------------------------------------------------------

  Widget _scanSection(DashTokens t, AppLocalizations l10n) {
    final progress = _scanProgress;
    final subnets = _discovery!.subnets;
    final isDocker = _discovery!.isDocker;
    // Custom entry when the user picked "Custom…" or there are no detected
    // subnets to choose from.
    final custom = _useCustomSubnet || subnets.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionLabel(t, l10n.addPrinterScanTitle),
        const SizedBox(height: 8),
        // Detected subnets → dropdown (+ "Custom…" sentinel). No detected
        // subnets → a plain CIDR field below is the only input.
        if (subnets.isNotEmpty)
          dashCombo<String>(
            context,
            id: 'add_printer.subnet',
            initialSelection: _useCustomSubnet ? _customSubnetOption : _subnet,
            enabled: !_scanning,
            label: Text(l10n.addPrinterSubnet),
            textStyle: _fieldTextStyle(t),
            onSelected: (v) => setState(() {
              if (v == _customSubnetOption) {
                _useCustomSubnet = true;
              } else {
                _useCustomSubnet = false;
                _subnet = v;
              }
            }),
            entries: [
              // The menu is a route of its own, so the field's tag does not
              // reach these — each option carries one on its label widget.
              for (final s in subnets)
                DropdownMenuEntry(
                  value: s,
                  label: s,
                  labelWidget: logTag('add_printer.subnet_option', Text(s)),
                ),
              DropdownMenuEntry(
                value: _customSubnetOption,
                label: l10n.addPrinterSubnetCustomOption,
                labelWidget: logTag(
                  'add_printer.subnet_custom_option',
                  Text(l10n.addPrinterSubnetCustomOption),
                ),
              ),
            ],
          ),
        if (custom) ...[
          if (subnets.isNotEmpty) const SizedBox(height: 8),
          TextField(
            controller: _customSubnet,
            enabled: !_scanning,
            autocorrect: false,
            keyboardType: TextInputType.url,
            style: _fieldTextStyle(t),
            decoration: dashFieldDecoration(
              t,
              labelText: l10n.addPrinterSubnetCustomLabel,
              hintText: '192.168.1.0/24',
            ),
          ).tagged('add_printer.custom_subnet'),
        ],
        const SizedBox(height: 6),
        Text(
          isDocker
              ? l10n.addPrinterSubnetDockerNote
              : l10n.addPrinterSubnetCustomNote,
          style: t.microSoft,
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _scanning ? null : _scan,
          icon: _scanning
              ? const DashSpinner(size: 16)
              : const Icon(Icons.search),
          label: Text(_scanButtonLabel(l10n, progress)),
        ).tagged('add_printer.scan_network'),
        if (_scanError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _scanError!,
              style: TextStyle(
                fontFamily: DashTokens.fontUi,
                fontSize: 12,
                color: t.danger,
              ),
            ),
          ),
        if (_found.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final p in _found) _discoveredTile(t, p),
        ] else if (!_scanning && _hasScanned) ...[
          const SizedBox(height: 8),
          Text(
            l10n.addPrinterScanNoResults,
            style: t.labelSoft.copyWith(color: t.textSecondary),
          ),
        ],
      ],
    );
  }

  String _scanButtonLabel(AppLocalizations l10n, ScanStatus? progress) {
    if (_scanning) {
      return (_wantsSubnetScan && progress != null && progress.total > 0)
          ? l10n.addPrinterScanning(progress.scanned, progress.total)
          : l10n.addPrinterScanningPlain;
    }
    return _wantsSubnetScan
        ? l10n.addPrinterScanButton
        : l10n.addPrinterDiscoverNetwork;
  }

  Widget _discoveredTile(DashTokens t, DiscoveredPrinter p) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: t.subCard,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _applyDiscovered(p),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.print_outlined, size: 20, color: t.accentGreenInk),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.name.isNotEmpty ? p.name : p.serial,
                        style: t.titleSm,
                      ),
                      Text(
                        [
                          p.ipAddress,
                          if (p.model != null) p.model!,
                        ].join(' · '),
                        style: t.monoMicro.copyWith(color: t.textSecondary),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.add, size: 20, color: t.textTertiary),
              ],
            ),
          ),
        ).tagged('add_printer.discovered'),
      ),
    );
  }

  // --- Diagnostic section -------------------------------------------------

  Widget _diagnosticSection(DashTokens t, AppLocalizations l10n) {
    final result = _diagnostic;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: _diagnosing ? null : _runDiagnostic,
          icon: _diagnosing
              ? const DashSpinner(size: 16)
              : const Icon(Icons.troubleshoot),
          label: Text(
            _diagnosing
                ? l10n.addPrinterDiagnosticRunning
                : l10n.addPrinterDiagnostic,
          ),
        ).tagged('add_printer.diagnose'),
        if (_diagnosticError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _diagnosticError!,
              style: TextStyle(
                fontFamily: DashTokens.fontUi,
                fontSize: 12,
                color: t.danger,
              ),
            ),
          ),
        if (result != null) ...[
          const SizedBox(height: 10),
          Text(
            _overallText(l10n, result.overall),
            style: t.bodyBold.copyWith(color: _overallColor(t, result.overall)),
          ),
          const SizedBox(height: 6),
          for (final c in result.checks) _checkRow(t, l10n, c),
        ],
      ],
    );
  }

  Widget _checkRow(DashTokens t, AppLocalizations l10n, DiagnosticCheck c) {
    final (icon, color) = switch (c.status) {
      'pass' => (Icons.check_circle, t.accentGreenInk),
      'fail' => (Icons.cancel, t.danger),
      'warn' => (Icons.warning_amber_rounded, const Color(0xFFE0A800)),
      _ => (Icons.remove_circle_outline, t.textTertiary),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _checkTitle(l10n, c.id),
              style: t.bodyPlain.copyWith(color: t.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  String _overallText(AppLocalizations l10n, String overall) =>
      switch (overall) {
        'ok' => l10n.diagOverallOk,
        'warnings' => l10n.diagOverallWarnings,
        _ => l10n.diagOverallProblems,
      };

  Color _overallColor(DashTokens t, String overall) => switch (overall) {
    'ok' => t.accentGreenInk,
    'warnings' => const Color(0xFFE0A800),
    _ => t.danger,
  };

  /// Localized title for a diagnostic check id; falls back to the raw id when a
  /// new server check appears that we don't have a string for yet.
  String _checkTitle(AppLocalizations l10n, String id) => switch (id) {
    'port_mqtt' => l10n.diagCheckPortMqtt,
    'port_ftps' => l10n.diagCheckPortFtps,
    'port_rtsps' => l10n.diagCheckPortRtsps,
    'network_mode' => l10n.diagCheckNetworkMode,
    'subnet' => l10n.diagCheckSubnet,
    'mqtt_auth' => l10n.diagCheckMqttAuth,
    'developer_mode' => l10n.diagCheckDeveloperMode,
    _ => id,
  };

  // --- Shared field helpers ----------------------------------------------

  Widget _modelDropdown(DashTokens t, AppLocalizations l10n) {
    return dashCombo<String>(
      context,
      id: 'add_printer.model',
      initialSelection: _model,
      enabled: !_busy,
      label: Text(l10n.addPrinterModel),
      helperText: l10n.addPrinterModelOptional,
      textStyle: _fieldTextStyle(t),
      onSelected: (v) => setState(() => _model = v ?? _modelNone),
      entries: [
        DropdownMenuEntry(
          value: _modelNone,
          label: l10n.addPrinterModelNone,
          labelWidget: logTag(
            'add_printer.model_none',
            Text(l10n.addPrinterModelNone),
          ),
        ),
        for (final (series, models) in _modelGroups) ...[
          DropdownMenuEntry(
            value: '::$series',
            label: series,
            enabled: false,
            labelWidget: Text(
              series,
              style: t.label.copyWith(color: t.textSecondary),
            ),
          ),
          for (final (value, label) in models)
            DropdownMenuEntry(
              value: value,
              label: label,
              labelWidget: logTag('add_printer.model_option', Text(label)),
            ),
        ],
      ],
    );
  }

  Widget _field(
    DashTokens t, {
    required TextEditingController controller,
    required String label,
    String? hint,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputAction? textInputAction,
  }) {
    return TextFormField(
      controller: controller,
      enabled: !_busy,
      autocorrect: false,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      validator: validator,
      style: _fieldTextStyle(t),
      decoration: dashFieldDecoration(
        t,
        labelText: label,
        hintText: hint,
        suffixIcon: suffixIcon,
      ),
    ).tagged('add_printer.field');
  }

  TextStyle _fieldTextStyle(DashTokens t) => t.bodyStrong;

  Widget _sectionLabel(DashTokens t, String label) => Align(
    alignment: Alignment.centerLeft,
    child: Text(label, style: t.bodyBold),
  );
}
