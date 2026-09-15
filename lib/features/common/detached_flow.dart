import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The two handles a flow keeps when it may outlive the widget that started it.
typedef DetachedHandles = ({
  ProviderContainer providers,
  ScaffoldMessengerState messenger,
});

/// Takes both **before the first `await`**, for a flow that can outlive its own
/// widget: afterwards `ref` throws and `ScaffoldMessenger.of(context)` has no
/// context to read, so the rows stay stale and the user is told nothing —
/// including that the action failed.
///
/// This is about the handles, not the widget: a `setState` after the await
/// still needs its own `mounted` check, and `showApiFailure` still wants
/// `mounted ? messenger : null` so a refusal nobody saw is recorded as one.
DetachedHandles detachFrom(BuildContext context) => (
  providers: ProviderScope.containerOf(context, listen: false),
  messenger: ScaffoldMessenger.of(context),
);
