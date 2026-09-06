import 'package:flutter/material.dart';

/// Scrim behind a sheet: darker than Material's own, so the screen underneath
/// reads as a dimmed backdrop rather than a half-rendered glitch bleeding
/// through the top of a rounded sheet.
const Color dashSheetBarrier = Color(0xB3000000); // black @ 70%

/// A Material bottom sheet with the app's arguments: the framework's drag
/// handle, and content inset from the system navigation bar.
///
/// The inset is the reason this exists rather than a bare
/// [showModalBottomSheet]: since Android 15 the sheet is drawn edge to edge, so
/// its last row lands under the gesture pill unless something consumes the
/// padding. A [SafeArea] the content already carries stays harmless — the outer
/// one takes the inset and the inner sees nothing left.
///
/// [scrollControlled] is on by default because most sheets here outgrow the
/// 9/16 of the screen a sheet is otherwise capped at; pass false for a short
/// list of actions that should stay a modest strip at the bottom.
Future<T?> dashSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool scrollControlled = true,
  bool dismissible = true,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: scrollControlled,
  showDragHandle: true,
  isDismissible: dismissible,
  // Guards the top: a scroll-controlled sheet may reach full height, and
  // Material's own flag covers everything except the bottom, which the
  // SafeArea below takes instead.
  useSafeArea: true,
  builder: (ctx) => SafeArea(top: false, child: builder(ctx)),
);

/// A sheet for content that draws its own surface — a `SheetSurface`, usually
/// inside a `DraggableScrollableSheet`. The sheet itself is transparent and
/// unbounded; the surface owns the corners, the drag handle and the inset.
///
/// [barrierColor] defaults to the app's darker scrim; pass null to keep
/// Material's lighter one.
Future<T?> dashSurfaceSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  Color? barrierColor = dashSheetBarrier,
  bool dismissible = true,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  barrierColor: barrierColor,
  isDismissible: dismissible,
  builder: builder,
);
