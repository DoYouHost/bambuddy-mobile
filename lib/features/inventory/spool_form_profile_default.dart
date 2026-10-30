part of 'inventory_screen.dart';

/// "Use as default" in the spool form (server #1326): the form's slicer preset
/// and per-model presets become what new spools of this product start with.
///
/// The scope is a select under the switch, like every other field of the form,
/// and exists only while the switch is on. "Only {colour}" needs a colour
/// typed; without one the default is for every colour, which is also what the
/// select shows.
class _ProfileDefaultRow extends StatelessWidget {
  const _ProfileDefaultRow({
    required this.product,
    required this.value,
    required this.onChanged,
    required this.forColor,
    required this.onScope,
  });

  final ProfileProduct product;
  final bool value;
  final ValueChanged<bool> onChanged;

  /// The user's pick; it counts only while the form has a colour name.
  final bool forColor;
  final ValueChanged<bool> onScope;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final needsMaterial = product.material.trim().isEmpty;
    final color = product.colorName.trim();
    final on = value && !needsMaterial;
    final colorOnly = forColor && color.isNotEmpty;
    return Column(
      children: [
        const SizedBox(height: DashSpace.sm),
        SwitchListTile(
          value: on,
          onChanged: needsMaterial ? null : onChanged,
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.inventoryProfileDefaultUse),
          subtitle: Text(
            needsMaterial
                ? l10n.inventoryProfileDefaultNeedsMaterial
                : l10n.inventoryProfileDefaultFor(product.label),
          ),
        ).tagged('spool_form.default'),
        if (on)
          dashCombo<bool>(
            context,
            id: 'spool_form.default_scope',
            // The menu keeps the label it was built with, so a new colour has
            // to build a new one.
            fieldKey: ValueKey('$color|$colorOnly'),
            label: Text(l10n.inventoryProfileDefaultScope),
            initialSelection: colorOnly,
            onSelected: (v) => onScope(v ?? false),
            entries: [
              DropdownMenuEntry(
                value: false,
                label: l10n.inventoryProfileDefaultAllColors,
                labelWidget: logTag(
                  'spool_form.default_scope.all',
                  Text(l10n.inventoryProfileDefaultAllColors),
                ),
              ),
              if (color.isNotEmpty)
                DropdownMenuEntry(
                  value: true,
                  label: l10n.inventoryProfileDefaultColorOnly(color),
                  labelWidget: logTag(
                    'spool_form.default_scope.color',
                    Text(l10n.inventoryProfileDefaultColorOnly(color)),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
