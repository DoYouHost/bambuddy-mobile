part of 'printer_card.dart';

/// The target editor of the card's sheets: a −/+ button on either side of a
/// slider, and the quick-pick presets under them. The temperature, Panda
/// Breath, fan and drying sheets all set a number this way. What differs
/// between them is data (the range, the unit in the labels, the colour, the
/// log ids), and each of those is a parameter; none of them is behaviour, so a
/// sheet cannot give this editor a rule of its own.
///
/// It keeps no value: the sheet owns the number and gets every change through
/// [onChanged], inside `[min, max]`. A preset is passed on as it is.
class _StepSlider extends StatelessWidget {
  const _StepSlider({
    required this.value,
    required this.max,
    required this.onChanged,
    required this.presets,
    required this.presetLabel,
    required this.idFor,
    required this.lessLabel,
    required this.moreLabel,
    this.min = 0,
    this.activeColor,
    this.semanticFormatter,
    this.presetGap = DashSpace.md,
  });

  /// May lie outside `[min, max]` (a chamber target set elsewhere above the
  /// ceiling): the slider shows it clamped, and the sheet keeps it until the
  /// user moves it.
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  final List<int> presets;
  final String Function(int preset) presetLabel;

  /// The diagnostic id of one control, by part: `step_down`, `slider`,
  /// `step_up` or `preset`. A function and not a prefix because ids are wire
  /// values: the temperature and fan sheets shipped as `temperature.step_up`,
  /// the drying rows as `drying.temp_step_up`, and renaming either would split
  /// the bug reports' vocabulary in two.
  final String Function(String part) idFor;

  /// The buttons' accessible names: a minus or a plus beside a slider says
  /// nothing alone.
  final String lessLabel;
  final String moreLabel;

  /// The theme's slider colour when null.
  final Color? activeColor;

  /// What a reader announces for the slider; without it the position is read as
  /// a percentage, which says nothing about a temperature or a duration.
  final String Function(double value)? semanticFormatter;

  final double presetGap;

  @override
  Widget build(BuildContext context) {
    int clamp(int v) => v.clamp(min, max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            _StepButton(
              icon: Icons.remove,
              id: idFor('step_down'),
              label: lessLabel,
              onTap: () => onChanged(clamp(value - 1)),
            ),
            Expanded(
              // No `divisions`: tick marks would be far denser on a wide range
              // (a nozzle's 0–300) than on a narrow one (a bed's 0–120) and look
              // inconsistent. The slider stays smooth and moves in whole units.
              child: Slider(
                value: clamp(value).toDouble(),
                min: min.toDouble(),
                max: max.toDouble(),
                activeColor: activeColor,
                semanticFormatterCallback: semanticFormatter,
                onChanged: (v) => onChanged(clamp(v.round())),
              ).tagged(idFor('slider')),
            ),
            _StepButton(
              icon: Icons.add,
              id: idFor('step_up'),
              label: moreLabel,
              onTap: () => onChanged(clamp(value + 1)),
            ),
          ],
        ),
        SizedBox(height: presetGap),
        // Tapping a preset moves the slider; the sheet commits with its own
        // Set button.
        Wrap(
          alignment: WrapAlignment.center,
          spacing: DashSpace.sm,
          runSpacing: DashSpace.sm,
          children: [
            for (final p in presets)
              _PresetChip(
                label: presetLabel(p),
                id: idFor('preset'),
                selected: value == p,
                onTap: () => onChanged(p),
              ),
          ],
        ),
      ],
    );
  }
}

/// The number a sheet is setting: large, mono, centred above its slider.
class _TargetNumeral extends StatelessWidget {
  const _TargetNumeral(this.text, {required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      text,
      style: TextStyle(
        fontFamily: DashTokens.fontMono,
        fontSize: DashFontSize.numeral,
        fontWeight: DashWeight.bold,
        color: color,
      ),
    ),
  );
}

/// A group of controls held still while [held]: dimmed, and out of reach of a
/// finger **and** of the keyboard. `IgnorePointer` alone leaves a focused
/// button answering Enter (measured on a probe, and found in review of the
/// Panda Breath sheet and the chamber's), so the focus goes with it.
class _HeldWhen extends StatelessWidget {
  const _HeldWhen({required this.held, required this.child});

  final bool held;
  final Widget child;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: held ? 0.35 : 1,
    child: IgnorePointer(
      ignoring: held,
      child: ExcludeFocus(excluding: held, child: child),
    ),
  );
}
