import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter/material.dart';

import '../../core/theme/dash_theme.dart';

/// A [DashTokens.cardBox] row in a list that opens something when tapped: the
/// ink ripple clipped to the card's corners, named [id] in the diagnostic log.
class TappableCard extends StatelessWidget {
  const TappableCard({
    super.key,
    required this.id,
    required this.onTap,
    required this.child,
  });

  final String id;

  /// `null` leaves the card inert, as for a row the session may not edit.
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: DashSpace.xs),
    child: Material(
      color: Colors.transparent,
      child: logTag(
        id,
        InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(DashSpace.lg),
            decoration: DashTokens.of(context).cardBox,
            child: child,
          ),
        ),
      ),
    ),
  );
}
