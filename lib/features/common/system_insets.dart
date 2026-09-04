import 'package:flutter/widgets.dart';

/// [base] with the system navigation inset added to its bottom.
///
/// Android 15 draws every app edge-to-edge, so a screen-level scroll view ends
/// at the bottom of the window rather than above the navigation bar: a constant
/// bottom padding leaves the last row under the gesture pill (~24 dp) or the
/// three-button bar (~48 dp). Screens hosted by the shell do not need this —
/// its tab bar already sits on the inset.
///
/// `viewPadding` rather than `padding`, for the same reason as that tab bar: an
/// open keyboard collapses `padding` to zero and the spacing would jump.
EdgeInsets withSystemNavInset(BuildContext context, EdgeInsets base) => base
    .copyWith(bottom: base.bottom + MediaQuery.viewPaddingOf(context).bottom);
