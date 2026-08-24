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
