/// Application-wide constants.
///
/// Centralised so that no module hard-codes magic numbers or strings.
abstract final class AppConstants {
  static const String appName = 'TeachTrack';

  /// How often the sync engine attempts to drain the outbox while online.
  static const Duration syncInterval = Duration(minutes: 5);

  /// Maximum number of queued operations dispatched in a single drain pass.
  /// Keeps Firestore batches well under the 500-operation hard limit.
  static const int syncBatchSize = 100;

  /// Retry policy for failed synchronisation attempts.
  static const Duration syncRetryBaseDelay = Duration(seconds: 5);
  static const Duration syncRetryMaxDelay = Duration(minutes: 30);
  static const int syncMaxAttempts = 8;
}

/// Logical entity names used as sync-queue routing keys.
///
/// Each feature registers a remote handler under one of these keys, which is
/// how `core` stays decoupled from feature-specific remote data sources.
abstract final class SyncEntityTypes {
  static const String classSession = 'class_session';
  static const String timetableEntry = 'timetable_entry';
  static const String period = 'period';
  static const String teacherProfile = 'teacher_profile';
  static const String attendance = 'attendance';
  static const String equipmentCheckout = 'equipment_checkout';
  static const String equipmentItem = 'equipment_item';
}
