/// Route paths and names in one place.
///
/// Named routes matter for push notifications: an FCM payload can carry a route
/// name and the app can deep-link to it without string literals scattered
/// across features.
abstract final class AppRoutes {
  static const String todayPath = '/';
  static const String todayName = 'today';

  static const String timetablePath = '/timetable';
  static const String timetableName = 'timetable';

  static const String peModulePath = '/pe';
  static const String peModuleName = 'pe';

  static const String settingsPath = '/settings';
  static const String settingsName = 'settings';

  /// Debug-only sync inspector.
  static const String diagnosticsPath = '/diagnostics';
  static const String diagnosticsName = 'diagnostics';
}
