import 'package:flutter/material.dart';

import '../../core/diagnostics/log_tag.dart';
import '../../core/theme/dash_text.dart';
import '../../core/theme/dash_theme.dart';

/// The three pieces a settings screen in this app is built from: a card that
/// groups related rows, a title/subtitle row with a switch, and an integer
/// slider.
///
/// They were written for the notification screen and are the app's settings
/// look; the server settings screen needs exactly the same three, which is why
/// they moved here rather than being copied.

/// The words that introduce a group of rows.
class SettingsSectionHeader extends StatelessWidget {
  const SettingsSectionHeader(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Semantics(
        header: true,
        child: Text(
          text.toUpperCase(),
          style: t.label.copyWith(color: t.accentGreenInk, letterSpacing: 0.4),
        ),
      ),
    );
  }
}

/// Card grouping related rows, hairline-separated — the same container as the
/// maintenance screen's printer cards.
class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        gradient: t.cardGradient,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: t.cardBorder),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(height: 1, indent: 12, endIndent: 12, color: t.hairline),
            rows[i],
          ],
        ],
      ),
    );
  }
}

/// Title/subtitle row with a green pill switch on the right, replacing
/// [SwitchListTile] to match the Dash card look.
///
/// A null [onChanged] both disables and dims it: every screen using this has a
/// row whose setting is real but currently has no effect, and greying it is how
/// that is said without taking the value off the screen.
class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    super.key,
    required this.tag,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  /// Name this row taps under in a diagnostic log. The visible label is
  /// localized and is never recorded.
  final String tag;

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final enabled = onChanged != null;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      // No `MergeSemantics` here, though the row looks like the case for it.
      // `Semantics(identifier:)` merges the title and the sentence under it
      // into the tappable node already; wrapping the lot in `MergeSemantics`
      // moved the identifier onto a node of its own and left the label on
      // another — the exact split `logTag` warns about, which costs the log the
      // ability to say which row was pressed. The switch keeps a second node
      // either way: that is `Switch`, not this row, and `SwitchListTile` reads
      // identically (measured).
      child: logTag(
        tag,
        InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: enabled ? () => onChanged!(!value) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: t.titleSm),
                      const SizedBox(height: 3),
                      Text(subtitle, style: t.label),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Switch(
                  value: value,
                  onChanged: onChanged,
                  activeThumbColor: t.accentGreen,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Integer slider with the value spelled out in [label] above it, and an
/// optional [subtitle] under that. Disabled keeps the value on screen — a
/// threshold whose event is off still says what it would be.
///
/// The subtitle is not decoration. A slider says "4" where a switch says
/// on/off, and a number is the harder of the two to guess the meaning of: the
/// row reading "Files uploaded to 2 printers at once" told nobody what it
/// changed. Where a switch row has a sentence, a slider row needs one more.
///
/// [onChangeEnd] is what a server-backed setting writes on: dragging produces a
/// value per pixel, and a request per pixel is not a save, it is a flood.
/// Screens whose value is local pass [onChanged] alone.
class SettingsSlider extends StatelessWidget {
  const SettingsSlider({
    super.key,
    required this.tag,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.enabled,
    required this.onChanged,
    this.subtitle,
    this.bubble,
    this.step = 1,
    this.onChangeEnd,
  });

  /// Name this slider taps under in a diagnostic log.
  final String tag;

  final String label;

  /// What the value indicator over the thumb reads while dragging. Defaults to
  /// the bare number, which is only right when the number is the unit: a
  /// duration slider showed `900` over a row that said `15min`.
  final String? bubble;

  /// What the number actually changes. Null only where the label alone is the
  /// whole story.
  final String? subtitle;

  final int value;
  final int min;
  final int max;

  /// How far one division moves the value. A range of hundreds needs one wider
  /// than a degree, or the thumb cannot land on a round number.
  final int step;

  final bool enabled;
  final void Function(int) onChanged;
  final void Function(int)? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final end = onChangeEnd;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Padding(
        // The same horizontal inset as a switch row, so a label and a title in
        // one card start on the same line.
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: t.titleSm),
            if (subtitle case final text?) ...[
              const SizedBox(height: 3),
              Text(text, style: t.label),
            ],
            const SizedBox(height: 2),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                // Zero, so the track spans the row rather than being inset by
                // the overlay width — which left it starting well right of the
                // label above it. The M3 rounded track keeps the thumb inside
                // its own bounds (`slider.dart`, `trackRect.height` inset), so
                // nothing is clipped at either end.
                padding: EdgeInsets.zero,
                activeTrackColor: t.accentGreen,
                inactiveTrackColor: t.gaugeTrack,
                // One slider had few enough divisions to draw its ticks and
                // the next had too many, so two rows of the same control did
                // not look like the same control.
                activeTickMarkColor: Colors.transparent,
                inactiveTickMarkColor: Colors.transparent,
                thumbColor: t.accentGreen,
                overlayColor: t.accentGreen.withValues(alpha: 0.15),
                valueIndicatorColor: t.accentGreen,
                valueIndicatorTextStyle: const TextStyle(
                  fontFamily: DashTokens.fontMono,
                  color: Color(0xFF0A0C08),
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: Slider(
                value: value.clamp(min, max).toDouble(),
                min: min.toDouble(),
                max: max.toDouble(),
                divisions: (max - min) ~/ step,
                label: bubble ?? '$value',
                // The row's own words, so a screen reader says what is being
                // set and not just a number floating on its own.
                semanticFormatterCallback: (_) => label,
                onChanged: enabled ? (v) => onChanged(_snap(v)) : null,
                onChangeEnd: enabled && end != null
                    ? (v) => end(_snap(v))
                    : null,
              ).tagged(tag),
            ),
          ],
        ),
      ),
    );
  }

  /// Back to a value the server accepts. `divisions` already quantizes the
  /// thumb, but only relative to [min] — rounding without subtracting it first
  /// lands off-grid whenever [min] is not a multiple of [step].
  int _snap(double v) => min + ((v - min) / step).round() * step;
}
