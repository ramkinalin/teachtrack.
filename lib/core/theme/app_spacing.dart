/// Spacing and radius tokens on a 4dp grid.
///
/// Every widget uses these instead of literal padding values so that density
/// can be tuned globally.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

abstract final class AppRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 20;
  static const double pill = 999;
}

/// Responsive layout breakpoints (shortest side, in logical pixels).
abstract final class AppBreakpoints {
  static const double compact = 600; // phones
  static const double medium = 840; // small tablets / foldables
}
