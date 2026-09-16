import 'package:flutter/material.dart';

import '../wear_theme.dart';

/// Watch-sized busy indicator, shown wherever a wear screen waits for something.
/// Sized down by hand: the Material default is drawn for a phone and eats most
/// of a 384 px face.
const wearSpinner = Center(
  child: Padding(
    padding: EdgeInsets.all(8),
    child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator()),
  ),
);

/// The other way a watch screen says it is working: a veil over the whole face,
/// for a command already on its way to a printer.
///
/// Deliberately not the same as [wearSpinner], which replaces one button while
/// the rest of the screen stays usable. A printer command has to take the whole
/// screen with it — every other button on that screen acts on the same printer,
/// and a second tap mid-command is how a print gets stopped twice.
const wearBusyVeil = Positioned.fill(
  child: ColoredBox(
    color: wearScrim,
    child: Center(
      child: SizedBox(
        width: 30,
        height: 30,
        child: CircularProgressIndicator(),
      ),
    ),
  ),
);

/// The third thing a wear screen says about itself: this is last run's data,
/// drawn while the first poll is still out ([WearFleetCache]).
///
/// Dims rather than blocks. An unreachable server leaves [WearFleet.stale] set
/// for as long as the refresh keeps failing, and a screen that had also stopped
/// taking taps would have taken pull-to-refresh down with it — leaving the one
/// state nobody can get out of. Dimming says "not confirmed" and leaves every
/// way forward open.
Widget wearDimIfStale({required bool stale, required Widget child}) =>
    stale ? Opacity(opacity: _staleOpacity, child: child) : child;

/// Deliberately gentle. The dim is no longer the only signal — a cached frame
/// also disables every command button and says why — and a disabled label is
/// already drawn at 38% alpha, which this multiplies. At 0.45 that product was
/// 0.17 and the buttons were gone rather than greyed.
const _staleOpacity = 0.6;
