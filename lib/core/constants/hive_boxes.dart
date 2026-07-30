/// Hive box names and type-adapter ids.
///
/// Type ids must never be reused or renumbered once shipped: existing installs
/// hold binary data keyed by these ids, and changing them corrupts local data.
abstract final class HiveBoxes {
  static const String pendingOperations = 'pending_operations';
  static const String settings = 'settings';
  static const String syncMeta = 'sync_meta';

  // Timetable feature.
  static const String periods = 'periods';
  static const String timetableEntries = 'timetable_entries';
  static const String classSessions = 'class_sessions';
}

abstract final class HiveTypeIds {
  // 1-9 reserved for core infrastructure.
  static const int syncOperationType = 1;
  static const int pendingOperation = 2;

  // 10+ for feature models, so core ids stay stable.
  static const int period = 10;
  static const int timetableEntry = 11;
  static const int classSession = 12;
  static const int classSessionStatus = 13;
}

/// Keys used inside the [HiveBoxes.syncMeta] box.
abstract final class SyncMetaKeys {
  static const String lastSuccessfulSyncAt = 'last_successful_sync_at';
}

/// Keys used inside the [HiveBoxes.settings] box.
///
/// Single-record configuration lives here as plain JSON rather than in dedicated
/// boxes with generated adapters. There is nothing to query and only ever one
/// row, so a box and a TypeAdapter would be pure overhead.
abstract final class SettingsKeys {
  static const String onboardingCompleted = 'onboarding_completed';
  static const String teacherProfile = 'teacher_profile';
  static const String subjects = 'subjects';
}
