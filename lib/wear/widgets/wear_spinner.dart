import 'package:flutter/material.dart';

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
    color: Color(0x99000000),
    child: Center(
      child: SizedBox(
          width: 30, height: 30, child: CircularProgressIndicator()),
    ),
  ),
);
