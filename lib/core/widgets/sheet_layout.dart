import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Padding for the contents of a bottom sheet.
///
/// The bottom inset takes the *larger* of the keyboard height and the system
/// navigation inset. Padding only for the keyboard leaves the sheet's buttons
/// sitting underneath the gesture bar or the on-screen nav buttons — visible but
/// half-cut and awkward to hit. Padding only for the nav bar puts them behind the
/// keyboard instead. Taking the maximum handles both, and they never apply at the
/// same time: when the keyboard is up it is taller than the nav bar and covers it.
EdgeInsets sheetContentPadding(BuildContext context) {
  final double keyboard = MediaQuery.viewInsetsOf(context).bottom;
  final double systemNav = MediaQuery.viewPaddingOf(context).bottom;

  return EdgeInsets.only(
    left: AppSpacing.md,
    right: AppSpacing.md,
    top: AppSpacing.md,
    bottom: AppSpacing.md + math.max(keyboard, systemNav),
  );
}
