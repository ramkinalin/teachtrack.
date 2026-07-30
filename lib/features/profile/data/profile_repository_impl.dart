import 'dart:convert';

import 'package:hive_ce/hive.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/hive_boxes.dart';
import '../../../core/errors/failures.dart';
import '../../../core/services/sync/sync_queue_service.dart';
import '../../../core/utils/result.dart';
import '../../../shared/models/pending_operation.dart';
import '../domain/profile_repository.dart';
import '../domain/teacher_profile.dart';

/// Profile persistence over the shared settings box.
///
/// Stored as a JSON string rather than a Hive-typed object: it is a single record
/// with no queries, so a dedicated box and TypeAdapter would add binary
/// compatibility risk for no benefit.
class ProfileRepositoryImpl implements ProfileRepository {
  ProfileRepositoryImpl({
    required Box<dynamic> settingsBox,
    required SyncQueueService syncQueue,
    Uuid? uuid,
  })  : _settings = settingsBox,
        _syncQueue = syncQueue,
        _uuid = uuid ?? const Uuid();

  final Box<dynamic> _settings;
  final SyncQueueService _syncQueue;
  final Uuid _uuid;

  @override
  TeacherProfile? profile() {
    final Object? raw = _settings.get(SettingsKeys.teacherProfile);
    if (raw is! String || raw.isEmpty) return null;

    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return TeacherProfile.fromJson(decoded);
    } on Object {
      // Corrupt or older-format data should not brick startup; setup runs again.
      return null;
    }
  }

  @override
  bool get isOnboardingCompleted =>
      _settings.get(SettingsKeys.onboardingCompleted) == true;

  @override
  Future<Result<TeacherProfile>> saveProfile({
    required String fullName,
    String staffId = '',
    String schoolName = '',
    String classTeacherOf = '',
  }) async {
    final String trimmedName = fullName.trim();
    if (trimmedName.isEmpty) {
      return const Err<TeacherProfile>(
        ValidationFailure('Your name is required', field: 'fullName'),
      );
    }

    try {
      // The id is minted once and preserved across every later edit: it is the
      // teacherId already stamped onto existing timetable entries.
      final TeacherProfile updated = TeacherProfile(
        id: profile()?.id ?? _uuid.v4(),
        fullName: trimmedName,
        staffId: staffId.trim(),
        schoolName: schoolName.trim(),
        classTeacherOf: classTeacherOf.trim(),
      );

      await _settings.put(
        SettingsKeys.teacherProfile,
        jsonEncode(updated.toJson()),
      );

      await _syncQueue.enqueue(
        entityType: SyncEntityTypes.teacherProfile,
        entityId: updated.id,
        operation: SyncOperationType.update,
        payload: updated.toJson(),
      );

      return Ok<TeacherProfile>(updated);
    } on Object catch (error) {
      return Err<TeacherProfile>(
        CacheFailure('Could not save your profile', cause: error),
      );
    }
  }

  @override
  Future<Result<void>> setOnboardingCompleted({required bool value}) async {
    try {
      await _settings.put(SettingsKeys.onboardingCompleted, value);
      return okVoid;
    } on Object catch (error) {
      return Err<void>(CacheFailure('Could not save setup state', cause: error));
    }
  }

  @override
  Future<Result<void>> reset() async {
    try {
      await _settings.delete(SettingsKeys.teacherProfile);
      await _settings.delete(SettingsKeys.onboardingCompleted);
      return okVoid;
    } on Object catch (error) {
      return Err<void>(CacheFailure('Could not reset setup', cause: error));
    }
  }

  @override
  Stream<void> watchChanges() => _settings
      .watch()
      .where(
        (BoxEvent event) =>
            event.key == SettingsKeys.teacherProfile ||
            event.key == SettingsKeys.onboardingCompleted,
      )
      .map((BoxEvent _) {});
}
