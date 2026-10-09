import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:app_util/app_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/models/printer_location.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common/api_failure_snack.dart';
import '../common/dash_input.dart';
import '../common/sheet_surface.dart';
import 'printer_location_icons.dart';
import 'printer_locations_providers.dart';

/// Answers with the location the server saved, or null when the form was
/// closed. [existing] makes it an edit: the rename, icon and colour go in one
/// `PATCH`.
Future<PrinterLocation?> openPrinterLocationForm(
  BuildContext context, {
  PrinterLocation? existing,
}) => dashSurfaceSheet<PrinterLocation>(
  context,
  builder: (_) => _PrinterLocationForm(existing: existing),
);

class _PrinterLocationForm extends ConsumerStatefulWidget {
  const _PrinterLocationForm({this.existing});

  final PrinterLocation? existing;

  @override
  ConsumerState<_PrinterLocationForm> createState() =>
      _PrinterLocationFormState();
}

class _PrinterLocationFormState extends ConsumerState<_PrinterLocationForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late String? _icon = widget.existing?.icon;
  late String? _color = widget.existing?.color;
  bool _saving = false;

  /// A 409 from the save, shown on the name field until the name is edited.
  bool _nameTaken = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(printerLocationsRepositoryProvider);
    final container = ProviderScope.containerOf(context);
    final existing = widget.existing;
    final name = _name.text.trim();
    setState(() => _saving = true);
    try {
      final PrinterLocation saved;
      if (existing == null) {
        saved = await repo.create(
          PrinterLocationDraft(name: name, icon: _icon, color: _color),
        );
      } else {
        saved = await repo.update(
          PrinterLocationDraft(
            name: existing.name,
            newName: name,
            icon: _icon,
            color: _color,
          ),
        );
      }
      container.invalidate(printerLocationsProvider);
      if (!mounted) return;
      Navigator.of(context).pop(saved);
      messenger.snack(
        existing == null
            ? l10n.printerLocationsCreated
            : l10n.printerLocationsSaved,
      );
    } on AppApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _nameTaken = e.statusCode == 409;
      });
      if (!_nameTaken) {
        showApiFailure(messenger, e, l10n, action: 'location_form.save');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final editing = widget.existing != null;

    return logTag(
      'sheet.location_form',
      DraggableSheetSurface(
        initialSize: 0.8,
        minSize: 0.4,
        builder: (context, controller) => Form(
          key: _formKey,
          child: ListView(
            controller: controller,
            padding: EdgeInsets.fromLTRB(
              DashSpace.gutter,
              0,
              DashSpace.gutter,
              DashSpace.xl + bottomInset,
            ),
            children: [
              Text(
                editing
                    ? l10n.printerLocationsEditTitle
                    : l10n.printerLocationsCreateTitle,
                style: t.display,
              ),
              const SizedBox(height: DashSpace.md),
              TextFormField(
                controller: _name,
                style: t.body,
                maxLength: printerLocationNameMax,
                autofocus: !editing,
                decoration: dashDecoration(
                  t,
                  labelText: l10n.printerLocationsFieldName,
                ),
                validator: (v) => (v ?? '').trim().isEmpty
                    ? l10n.inventoryFieldRequired
                    : null,
                forceErrorText: _nameTaken
                    ? l10n.printerLocationsNameTaken
                    : null,
                onChanged: (_) {
                  if (_nameTaken) setState(() => _nameTaken = false);
                },
              ).tagged('location_form.name'),
              const SizedBox(height: DashSpace.md),
              Text(l10n.printerLocationsFieldIcon, style: t.label),
              const SizedBox(height: DashSpace.sm),
              Wrap(
                spacing: DashSpace.sm,
                runSpacing: DashSpace.sm,
                children: [
                  for (final name in printerLocationIcons.keys)
                    _IconChoice(
                      name: name,
                      selected: _icon == name,
                      onTap: () => setState(() => _icon = name),
                    ),
                ],
              ),
              const SizedBox(height: DashSpace.lg),
              Text(l10n.printerLocationsFieldColor, style: t.label),
              const SizedBox(height: DashSpace.sm),
              Wrap(
                spacing: DashSpace.sm,
                runSpacing: DashSpace.sm,
                children: [
                  for (final hex in printerLocationColors)
                    _ColorChoice(
                      hex: hex,
                      selected: _color == hex,
                      // The same swatch again takes the colour off, as on the
                      // web page.
                      onTap: () =>
                          setState(() => _color = _color == hex ? null : hex),
                    ),
                  if (_color != null)
                    IconButton(
                      tooltip: l10n.printerLocationsNoColor,
                      onPressed: () => setState(() => _color = null),
                      icon: const Icon(Icons.close),
                    ).tagged('location_form.color_clear'),
                ],
              ),
              const SizedBox(height: DashSpace.xl),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? DashSpinner(size: 20, color: t.onAccent)
                      : Text(
                          editing
                              ? l10n.printerLocationsSave
                              : l10n.printerLocationsCreate,
                        ),
                ).tagged('location_form.save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A tap target of [_size]; the glyph inside is smaller.
const _size = 44.0;

class _IconChoice extends StatelessWidget {
  const _IconChoice({
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Tooltip(
      message: name,
      child: logTag(
        'location_form.icon',
        selected: selected,
        Material(
          color: selected ? t.accentGreen : t.subCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: selected ? t.accentGreen : t.subCardBorder),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: SizedBox.square(
              dimension: _size,
              child: Icon(
                printerLocationIcon(name),
                size: 22,
                color: selected ? t.onAccent : t.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ColorChoice extends StatelessWidget {
  const _ColorChoice({
    required this.hex,
    required this.selected,
    required this.onTap,
  });

  final String hex;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final color = colorFromHex(hex) ?? t.textTertiary;
    return Tooltip(
      message: hex,
      child: logTag(
        'location_form.color',
        selected: selected,
        Material(
          color: color,
          shape: CircleBorder(
            side: BorderSide(
              color: selected ? t.textPrimary : Colors.transparent,
              width: 3,
            ),
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox.square(
              dimension: _size,
              child: selected
                  ? Icon(
                      Icons.check,
                      size: 22,
                      color: color.computeLuminance() > 0.5
                          ? Colors.black
                          : Colors.white,
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
