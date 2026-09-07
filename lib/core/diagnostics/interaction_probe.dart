import 'dart:ui' show CheckedState;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';

import 'filament_material.dart';
import 'log_event.dart';
import 'log_store.dart';

/// Records every touch the user makes, naming the target from the semantics
/// tree.
///
/// The alternative — a log call at each of the ~180 `onPressed` sites — would
/// be forgotten in new code exactly where new bugs live, and would still miss
/// the most valuable case: a tap that produced nothing at all. Here a tap
/// always leaves a record, so "I pressed it and nothing happened" becomes
/// visible instead of being an absence of evidence.
///
/// Naming comes from `Semantics(identifier:)` alone — `docs/diagnostics-log.md`
/// has the rule and why labels are never recorded.
class InteractionProbe {
  InteractionProbe({
    required this.store,
    this.longPressAfter = const Duration(milliseconds: 500),
    this.dragSlop = 24.0,
    this.dragQuietPeriod = const Duration(seconds: 2),
  });

  final LogStore store;

  /// A held touch past this becomes `long_press` instead of `tap`.
  final Duration longPressAfter;

  /// Movement past this (logical pixels) makes it a drag, not a tap.
  final double dragSlop;

  /// Consecutive drags on the same target inside this window fold into one
  /// record.
  final Duration dragQuietPeriod;

  SemanticsHandle? _semantics;
  final Map<int, _Touch> _touches = {};

  String? _lastDragKey;
  Duration _lastDragAt = Duration.zero;
  int _foldedDrags = 0;

  bool get isAttached => _semantics != null;

  void attach() {
    if (_semantics != null) return;
    // The semantics tree is only built when something asks for it, and it is
    // our naming source — so hold it open for exactly the recording.
    _semantics = SemanticsBinding.instance.ensureSemantics();
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
  }

  void detach() {
    final handle = _semantics;
    if (handle == null) return;
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    handle.dispose();
    _semantics = null;
    _touches.clear();
  }

  void _onPointer(PointerEvent event) {
    // Runs on every pointer event in the app, so a throw here would break input
    // itself: a missing record is a bad log, a crash is a bad app.
    try {
      if (event is PointerDownEvent) {
        _touches[event.pointer] = _Touch(
          at: event.position,
          startedAt: event.timeStamp,
          // The record's own offset. The pointer's `timeStamp` counts from the
          // engine's epoch, not from the session header.
          startedMs: store.elapsedMs,
          // Resolved at down time on purpose: by the time the finger lifts, a
          // dialog may cover what was actually pressed.
          target: _targetAt(event.position, event.viewId),
        );
      } else if (event is PointerUpEvent) {
        final touch = _touches.remove(event.pointer);
        if (touch != null) _emit(touch, event.position, event.timeStamp);
      } else if (event is PointerCancelEvent) {
        _touches.remove(event.pointer);
      }
    } on Object {
      _touches.remove(event.pointer);
    }
  }

  void _emit(_Touch touch, Offset endedAt, Duration endedTime) {
    // Operating the recorder is not using the app, and the recorder writes its
    // own records for the parts that matter.
    if (_isOwnUi(touch.target?.id)) return;

    final travelled = (endedAt - touch.at).distance;
    final heldMs = (endedTime - touch.startedAt).inMilliseconds;

    if (travelled >= dragSlop) {
      _emitDrag(touch, endedAt - touch.at, endedTime);
      return;
    }

    final isLongPress = heldMs >= longPressAfter.inMilliseconds;
    store.add(
      LogSource.ui,
      isLongPress ? 'long_press' : 'tap',
      // The widget's handler has already run by the time pointer-up reaches
      // this probe, so "now" would file the touch after everything it set off.
      at: touch.startedMs,
      fields: {
        ...?touch.target?.toFields(),
        if (isLongPress) 'held_ms': heldMs,
      },
    );
  }

  void _emitDrag(_Touch touch, Offset delta, Duration endedTime) {
    final key = touch.target?.dragKey ?? '';
    if (_lastDragKey == key && endedTime - _lastDragAt < dragQuietPeriod) {
      _foldedDrags++;
      _lastDragAt = endedTime;
      return;
    }

    store.add(
      LogSource.ui,
      'drag',
      at: touch.startedMs,
      fields: {
        ...?touch.target?.toFields(forDrag: true),
        'dir': _directionOf(delta),
        'dist': delta.distance.round(),
        if (_foldedDrags > 0) 'folded': _foldedDrags,
      },
    );
    _lastDragKey = key;
    _lastDragAt = endedTime;
    _foldedDrags = 0;
  }

  /// The recording controls name themselves with this prefix — see
  /// `features/bug_report/`. Matching on the identifier (which is inherited
  /// down the hit path) covers the whole bar, buttons included.
  static const ownUiPrefix = 'bug_report.';

  static bool _isOwnUi(String? id) => id?.startsWith(ownUiPrefix) ?? false;

  static String _directionOf(Offset delta) {
    if (delta.dx.abs() > delta.dy.abs()) {
      return delta.dx > 0 ? 'right' : 'left';
    }
    return delta.dy > 0 ? 'down' : 'up';
  }

  TouchTarget? _targetAt(Offset position, int viewId) {
    final view = _renderViewFor(viewId);
    final root = view?.owner?.semanticsOwner?.rootSemanticsNode;
    if (view == null || root == null) return null;

    // Semantics geometry is in physical pixels, pointer positions are logical.
    final point = position * view.flutterView.devicePixelRatio;
    final hit = _nodeAt(root, point, Matrix4.identity(), null);
    if (hit == null) return null;
    final node = _pressed(hit.node);
    return TouchTarget.of(node, inheritedId: hit.id ?? _menuItemId(node));
  }

  /// Identifier of a menu row's content, found without asking where the finger
  /// landed inside the row.
  ///
  /// A dropdown option puts the tap on the row and its label in a child node of
  /// its own, with no `MergeSemantics` between them (`PopupMenuItem` has one,
  /// which is why that shape always worked). The row is 48 logical pixels tall
  /// and the label 24, so the tag covers half of it — picking an AMS slot
  /// reported a bare `menuItem` three times out of three in a live run.
  ///
  /// Only when nothing on the hit path named the target: a row holds exactly
  /// one option, so the first identifier below it is that option's.
  static String? _menuItemId(SemanticsNode node) {
    if (node.getSemanticsData().role != SemanticsRole.menuItem) return null;
    String? found;
    void search(SemanticsNode current) {
      final identifier = current.getSemanticsData().identifier;
      if (identifier.isNotEmpty) {
        found = identifier;
        return;
      }
      current.visitChildren((child) {
        search(child);
        return found == null;
      });
    }

    search(node);
    return found;
  }

  static RenderView? _renderViewFor(int viewId) {
    for (final view in RendererBinding.instance.renderViews) {
      if (view.flutterView.viewId == viewId) return view;
    }
    return null;
  }

  /// Deepest node containing [point], preferring one that has something to
  /// call itself. `inherited` maps the parent's coordinate space to the root;
  /// `inheritedId` is the nearest ancestor's identifier.
  static _Hit? _nodeAt(
    SemanticsNode node,
    Offset point,
    Matrix4 inherited,
    String? inheritedId,
  ) {
    if (node.isInvisible) return null;

    final transform = inherited.clone();
    if (node.transform != null) transform.multiply(node.transform!);
    if (!MatrixUtils.transformRect(transform, node.rect).contains(point)) {
      return null;
    }

    final data = node.getSemanticsData();
    if (data.flagsCollection.isHidden) return null;

    // `Semantics(identifier: 'x', child: Button())` forms a node of its own
    // around the button rather than putting the id on it, so an identifier is
    // carried down and used when the node we land on has none.
    final idHere = data.identifier.isNotEmpty ? data.identifier : inheritedId;

    // A merged subtree is one control as far as the user is concerned, so an
    // icon-plus-text button reports as the button, not as its Text.
    if (!node.mergeAllDescendantsIntoThisNode) {
      final children = <SemanticsNode>[];
      node.visitChildren((child) {
        children.add(child);
        return true;
      });
      // Later children paint on top, so search back to front like a hit test,
      // and keep looking past whatever merely *covers* the thing that reacts.
      // Two real cases used to swallow the answer: a card's fill-level bar sits
      // over the card's own ink well, and an open route's node claims the whole
      // screen including where only the barrier behind it is painted. Rects
      // other than the route's are truthful, so this cannot steal a tap that
      // landed inside a sheet.
      _Hit? covering;
      for (final child in children.reversed) {
        final hit = _nodeAt(child, point, transform, idHere);
        if (hit == null) continue;
        if (_isInteractive(hit.node)) return hit;
        covering ??= hit;
      }
      if (covering != null) {
        // The node that takes the press wins over inert cover, but the name
        // comes from the deepest identifier on the path, which may sit *below*
        // it — see [_menuItemId] for the shape that needs this.
        return _isInteractive(node)
            ? _Hit(node, covering.id ?? idHere)
            : covering;
      }
    }
    return _Hit(node, idHere);
  }

  /// The node that actually takes the press: geometry can land us on something
  /// inert inside a control, and the log needs the control. Stops at the
  /// enclosing scrollable — a list is not what the user pressed.
  static SemanticsNode _pressed(SemanticsNode node) {
    if (_isInteractive(node)) return node;
    for (var n = node.parent; n != null; n = n.parent) {
      if (_scrolls(n)) break;
      if (_isInteractive(n)) return n;
    }
    return node;
  }

  static bool _scrolls(SemanticsNode node) {
    final data = node.getSemanticsData();
    return data.hasAction(SemanticsAction.scrollUp) ||
        data.hasAction(SemanticsAction.scrollDown) ||
        data.hasAction(SemanticsAction.scrollLeft) ||
        data.hasAction(SemanticsAction.scrollRight);
  }

  /// Whether this node is something the user can operate. Not the same as
  /// "has a label": a card's fill-level bar is labelled and inert.
  static bool _isInteractive(SemanticsNode node) {
    final data = node.getSemanticsData();
    return data.flagsCollection.isTextField ||
        data.hasAction(SemanticsAction.tap) ||
        data.hasAction(SemanticsAction.longPress) ||
        data.hasAction(SemanticsAction.increase) ||
        data.hasAction(SemanticsAction.decrease) ||
        data.hasAction(SemanticsAction.dismiss);
  }
}

/// What we learned about the thing under the finger. Accessibility labels are
/// **not** part of this on purpose, and [material] is the single exception —
/// `docs/diagnostics-log.md`.
class TouchTarget {
  const TouchTarget({
    this.id,
    this.material,
    this.role,
    this.checked,
    this.empty = false,
    this.dragKey = '',
  });

  factory TouchTarget.of(SemanticsNode node, {String? inheritedId}) {
    final data = node.getSemanticsData();
    final flags = data.flagsCollection;
    final identifier = data.identifier.isEmpty ? inheritedId : data.identifier;
    final tag = identifier == null ? null : FilamentMaterial.split(identifier);
    return TouchTarget(
      id: tag?.id,
      material: tag?.material,
      role: _roleOf(data),
      // `_pressed` already climbed as far as it could, so landing on something
      // inert means the finger hit a gap.
      empty: !InteractionProbe._isInteractive(node),
      checked: switch (flags.isChecked) {
        CheckedState.none => null,
        CheckedState.isTrue => true,
        CheckedState.isFalse || CheckedState.mixed => false,
      },
      // Node ids are stable while attached, which the label is not: flicking a
      // list puts a different item under the finger every time, so keying by
      // label would never fold anything.
      dragKey: '#${(_scrollableAncestor(node) ?? node).id}',
    );
  }

  /// Nearest ancestor that scrolls. A drag is a scroll of *that*, whatever
  /// item happened to be under the finger when it started.
  static SemanticsNode? _scrollableAncestor(SemanticsNode node) {
    for (
      var current = node;
      current.parent != null;
      current = current.parent!
    ) {
      final data = current.getSemanticsData();
      if (data.hasAction(SemanticsAction.scrollUp) ||
          data.hasAction(SemanticsAction.scrollDown) ||
          data.hasAction(SemanticsAction.scrollLeft) ||
          data.hasAction(SemanticsAction.scrollRight)) {
        return current;
      }
    }
    return null;
  }

  /// Declared via `Semantics(identifier:)`. Stable and not localized.
  final String? id;

  /// The only piece of on-screen content this log carries, and only from
  /// [FilamentMaterial]'s closed list.
  final String? material;
  final String? role;

  /// State *before* the tap: the handler has not run yet at pointer-down.
  final bool? checked;

  /// Nothing under the finger could be operated — the body of a card between
  /// its controls, the empty part of an open sheet, a screen's background.
  /// Recorded so the log says so instead of leaving the reader to guess from an
  /// absent `role`.
  final bool empty;

  /// Identity used to fold repeated drags — the scrollable being dragged, not
  /// the item that happened to be under the finger. Not logged.
  final String dragKey;

  /// [forDrag] drops the two fields that only mean something for a press. A
  /// drag record stands for a folded burst of flicks over different rows, so
  /// the material under the first finger-down would speak for rows nobody
  /// touched; and `empty` says nothing about a drag, since the scrollable
  /// ancestor handles it either way — a live run had one dashboard flick
  /// reported once as `empty` and once as a `button`.
  ///
  /// `empty` is written only when true, or every line would carry a field
  /// saying "this one did hit something".
  Map<String, Object?> toFields({bool forDrag = false}) => {
    'id': id,
    'mat': forDrag ? null : material,
    'role': role,
    'was_checked': checked,
    'empty': !forDrag && empty ? true : null,
  };

  /// Declared roles that name a *control*. Anything else describes what a node
  /// shows, and a card whose deepest painted thing is a progress bar merges
  /// that role into the tappable node — a tap on the card must still read as a
  /// button.
  static const _controlRoles = {
    SemanticsRole.tab,
    SemanticsRole.menuItem,
    SemanticsRole.menuItemCheckbox,
    SemanticsRole.menuItemRadio,
    SemanticsRole.comboBox,
    SemanticsRole.spinButton,
    SemanticsRole.dragHandle,
  };

  static String? _roleOf(SemanticsData data) {
    final flags = data.flagsCollection;
    // Text fields first: their content must never be logged, and the role tells
    // a reader the value was deliberately left out.
    if (flags.isTextField) return 'textField';
    if (_controlRoles.contains(data.role)) return data.role.name;
    if (flags.isSlider) return 'slider';
    if (flags.isChecked != CheckedState.none) return 'checkbox';
    if (flags.isLink) return 'link';
    // A scrim closing a sheet is tappable *and* dismissible; a control of ours
    // that is both (a swipe-to-delete card) carries an identifier.
    if (data.hasAction(SemanticsAction.dismiss) && data.identifier.isEmpty) {
      return 'dismiss';
    }
    if (flags.isButton || data.hasAction(SemanticsAction.tap)) return 'button';
    if (data.role != SemanticsRole.none) return data.role.name;
    // Nothing under the finger but the open route itself — a tap in the empty
    // area of a sheet, or on a barrier that is already animating away.
    if (flags.scopesRoute) return 'route';
    if (flags.isHeader) return 'header';
    if (flags.isImage) return 'image';
    return null;
  }
}

/// A node from the hit path plus the most specific identifier found along that
/// path — usually from an ancestor, but a control whose tag sits on its label
/// (a dropdown option) contributes one from below.
class _Hit {
  const _Hit(this.node, this.id);

  final SemanticsNode node;
  final String? id;
}

class _Touch {
  const _Touch({
    required this.at,
    required this.startedAt,
    required this.startedMs,
    this.target,
  });

  final Offset at;

  /// Engine timestamp of the down event, for how long the touch lasted.
  final Duration startedAt;

  /// The same moment as an offset into the session, which is what a record is
  /// stamped with.
  final int startedMs;

  final TouchTarget? target;
}
