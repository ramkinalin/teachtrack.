import 'dart:convert';

import 'package:hive_ce/hive.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/hive_boxes.dart';
import '../../../core/errors/failures.dart';
import '../../../core/services/sync/sync_queue_service.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/day_time.dart';
import '../../../core/utils/result.dart';
import '../../../shared/models/pending_operation.dart';
import '../../events/data/local/event_local_data_source.dart';
import '../../events/domain/entities/school_event.dart';
import '../../timetable/data/local/override_local_data_source.dart';
import '../../timetable/data/local/subject_store.dart';
import '../../timetable/data/local/timetable_local_data_source.dart';
import '../../timetable/domain/entities/class_session.dart';
import '../../timetable/domain/entities/period.dart';
import '../../timetable/domain/entities/schedule_override.dart';
import '../../timetable/domain/entities/timetable_entry.dart';
import '../../timetable/domain/repositories/override_repository.dart';
import '../../timetable/domain/repositories/timetable_repository.dart';
import '../domain/backup_payload.dart';
import '../domain/backup_repository.dart';

class BackupRepositoryImpl implements BackupRepository {
  BackupRepositoryImpl({
    required Box<dynamic> settingsBox,
    required SubjectStore subjects,
    required TimetableLocalDataSource timetableLocal,
    required EventLocalDataSource eventLocal,
    required OverrideLocalDataSource overrideLocal,
    required TimetableRepository timetable,
    required OverrideRepository overrides,
    required SyncQueueService syncQueue,
    Clock clock = const Clock(),
  })  : _settings = settingsBox,
        _subjects = subjects,
        _timetableLocal = timetableLocal,
        _eventLocal = eventLocal,
        _overrideLocal = overrideLocal,
        _timetable = timetable,
        _overrides = overrides,
        _syncQueue = syncQueue,
        _clock = clock;

  final Box<dynamic> _settings;
  final SubjectStore _subjects;
  final TimetableLocalDataSource _timetableLocal;
  final EventLocalDataSource _eventLocal;
  final OverrideLocalDataSource _overrideLocal;
  final TimetableRepository _timetable;
  final OverrideRepository _overrides;
  final SyncQueueService _syncQueue;
  final Clock _clock;

  @override
  BackupPayload snapshot() => BackupPayload(
        exportedAt: _clock.now(),
        profile: _profileJson(),
        subjects: _subjects.subjects(),
        periods: _timetableLocal.periods(),
        entries: _timetableLocal.allEntries(),
        sessions: _timetableLocal.allSessions(),
        events: _eventLocal.all(),
        overrides: _overrideLocal.all(),
      );

  @override
  String suggestedFileName() =>
      'teachtrack-backup-${CalendarDay.key(_clock.now())}.json';

  @override
  Future<Result<RestoreSummary>> restore(
    BackupPayload payload, {
    required RestoreMode mode,
  }) async {
    if (payload.isEmpty) {
      return const Err<RestoreSummary>(
        ValidationFailure('That backup is empty — nothing to restore.'),
      );
    }

    try {
      if (mode == RestoreMode.replace) {
        // Through the repository, so a delete is queued for everything removed.
        // A bare box clear would leave the outbox pushing records that no longer
        // exist once a backend is connected.
        await _timetable.clearAllData();
        for (final SchoolEvent event in _eventLocal.all()) {
          await _eventLocal.delete(event.id);
          await _syncQueue.enqueue(
            entityType: SyncEntityTypes.schoolEvent,
            entityId: event.id,
            operation: SyncOperationType.delete,
            payload: <String, dynamic>{'id': event.id},
          );
        }
      }

      int skipped = 0;

      // Periods first: entries reference them, and an entry whose period is
      // missing is dropped from the day view.
      int periods = 0;
      if (payload.periods.isNotEmpty) {
        final Result<void> result =
            await _timetable.replacePeriods(payload.periods);
        if (result.isOk) {
          periods = payload.periods.length;
        } else {
          skipped += payload.periods.length;
        }
      }

      int subjects = 0;
      for (final String subject in payload.subjects) {
        final Result<String> result = await _timetable.addSubject(subject);
        if (result.isOk) subjects++;
      }

      int entries = 0;
      for (final TimetableEntry entry in payload.entries) {
        if (mode == RestoreMode.merge &&
            _timetableLocal.entryById(entry.id) != null) {
          continue;
        }
        // Validated like any other write: a merge can legitimately collide with a
        // class already occupying that slot, and the app must never end up holding
        // two classes in one period.
        final Result<void> result = await _timetable.upsertEntry(entry);
        if (result.isOk) {
          entries++;
        } else {
          skipped++;
        }
      }

      int overrides = 0;
      for (final ScheduleOverride override in payload.overrides) {
        if (mode == RestoreMode.merge &&
            _overrideLocal.byId(override.id) != null) {
          continue;
        }
        final Result<void> result = await _overrides.upsert(override);
        if (result.isOk) {
          overrides++;
        } else {
          skipped++;
        }
      }

      int events = 0;
      for (final SchoolEvent event in payload.events) {
        if (mode == RestoreMode.merge && _eventLocal.byId(event.id) != null) {
          continue;
        }
        await _eventLocal.put(event);
        await _syncQueue.enqueue(
          entityType: SyncEntityTypes.schoolEvent,
          entityId: event.id,
          operation: SyncOperationType.create,
          payload: event.toJson(),
        );
        events++;
      }

      // Sessions last, and written directly: they are keyed on entry ids that
      // must already exist, and there is no repository call that writes one
      // without also deciding a status.
      int sessions = 0;
      for (final ClassSession session in payload.sessions) {
        if (mode == RestoreMode.merge &&
            _timetableLocal.sessionById(session.id) != null) {
          continue;
        }
        await _timetableLocal.putSession(session);
        await _syncQueue.enqueue(
          entityType: SyncEntityTypes.classSession,
          entityId: session.id,
          operation: SyncOperationType.create,
          payload: session.toJson(),
        );
        sessions++;
      }

      bool profileRestored = false;
      final Map<String, dynamic>? profile = payload.profile;
      if (profile != null) {
        await _settings.put(
          SettingsKeys.teacherProfile,
          jsonEncode(profile),
        );
        // Setup is complete by definition once a profile exists, or the teacher
        // would be sent back through the wizard after restoring.
        await _settings.put(SettingsKeys.onboardingCompleted, true);
        profileRestored = true;
      }

      return Ok<RestoreSummary>(
        RestoreSummary(
          entries: entries,
          sessions: sessions,
          events: events,
          overrides: overrides,
          periods: periods,
          subjects: subjects,
          skipped: skipped,
          profileRestored: profileRestored,
        ),
      );
    } on Object catch (error) {
      return Err<RestoreSummary>(
        CacheFailure('The restore did not finish', cause: error),
      );
    }
  }

  Map<String, dynamic>? _profileJson() {
    final Object? raw = _settings.get(SettingsKeys.teacherProfile);
    if (raw is! String || raw.isEmpty) return null;

    try {
      final Object? decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on Object {
      return null;
    }
  }
}
