import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The two handles a flow keeps when it may outlive the widget that started it.
typedef DetachedHandles = ({
  ProviderContainer providers,
  ScaffoldMessengerState messenger,
});

/// Takes both **before the first `await`**, for a flow that can outlive its own
/// widget.
///
/// The situation, which four flows had each explained to themselves: a sheet is
/// dismissed, or a card is rebuilt by the next status frame, while the request
/// it fired is still in the air. Afterwards
///
/// - `ref` throws (`Cannot use ref after the widget was disposed`), so the list
///   the server has just changed keeps the old rows until a manual refresh;
/// - `ScaffoldMessenger.of(context)` has no context to read, so the user is
///   told nothing at all — including that the action failed.
///
/// Both of the objects returned here belong to things above the screen — the
/// container to the app, the messenger to the `MaterialApp` — so both are still
/// there to use. Reading through the container also keeps each read live at the
/// point of use, rather than a snapshot taken before the flow began.
///
/// Destructure it, so the rest of the method reads as it always did:
///
/// ```dart
/// final (:providers, :messenger) = detachFrom(context);
/// ```
///
/// This is about the handles, not about the widget: a `setState` after the
/// await still needs its own `mounted` check, and `showApiFailure` still wants
/// `mounted ? messenger : null` so a refusal nobody saw is recorded as one.
DetachedHandles detachFrom(BuildContext context) => (
  providers: ProviderScope.containerOf(context, listen: false),
  messenger: ScaffoldMessenger.of(context),
);
