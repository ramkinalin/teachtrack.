import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/services/sync/sync_queue_service.dart';
import '../../../../core/utils/clock.dart';
import '../../../../core/utils/day_time.dart';
import '../../../../core/utils/result.dart';
import '../../../../shared/models/pending_operation.dart';
import '../../domain/entities/class_session.dart';
import '../../domain/entities/period.dart';
import '../../domain/entities/scheduled_class.dart';
import '../../domain/entities/timetable_entry.dart';
import '../../domain/repositories/timetable_repository.dart';
import '../local/subject_store.dart';
import '../local/timetable_local_data_source.dart';

/// Local-first timetable repository.
///
/// Every write follows the same two steps: commit to Hive, then append to the
/// outbox. The returned future resolves as soon as the local commit lands, so a
/// teacher tapping "class completed" on a field with no signal sees the UI update
/// immediately and the push happens whenever a connection appears.
class TimetableRepositoryImpl implements TimetableRepository {
  TimetableRepositoryImpl({
    required TimetableLocalDataSource local,
    required SubjectStore subjects,
    required SyncQueueService syncQueue,
    Clock clock = const Clock(),
  })  : _local = local,
        _subjects = subjects,
        _syncQueue = syncQueue,
        _clock = clock;

  final TimetableLocalDataSource _local;
  final SubjectStore _subjects;
  final SyncQueueService _syncQueue;
  final Clock _clock;

  @override
  List<Period> periods() => _local.periods();

  @override
  Period? periodById(String id) => _local.periodById(id);

  @override
  List<TimetableEntry> allEntries() => _local.allEntries();

  @override
  List<TimetableEntry> entriesForWeekday(int weekday) =>
      _local.entriesForWeekday(weekday);

  @override
  TimetableEntry? entryById(String id) => _local.entryById(id);

  @override
  List<ScheduledClass> scheduleFor(DateTime date) {
    final DateTime day = CalendarDay.dateOnly(date);
    final List<TimetableEntry> entries = _local.entriesForWeekday(day.weekday);

    final List<ScheduledClass> schedule = <ScheduledClass>[];
    for (final TimetableEntry entry in entries) {
      final Period? period = _local.periodById(entry.periodId);
      // An entry whose period was deleted is skipped rather than crashing the
      // day view; the editor surfaces it as needing a period.
      if (period == null) continue;

      schedule.add(
        ScheduledClass(
          entry: entry,
          period: period,
          date: day,
          session: _local.sessionById(ClassSession.buildId(day, entry.id)),
        ),
      );
    }

    schedule.sort(
      (ScheduledClass a, ScheduledClass b) =>
          a.period.sortOrder.compareTo(b.period.sortOrder),
    );
    return schedule;
  }

  @override
  Result<void> validateEntry(TimetableEntry entry) {
    if (entry.subject.trim().isEmpty) {
      return const Err<void>(
        ValidationFailure('Subject is required', field: 'subject'),
      );
    }
    if (entry.classGroup.trim().isEmpty) {
      return const Err<void>(
        ValidationFailure('Class is required', field: 'classGroup'),
      );
    }
    if (_local.periodById(entry.periodId) == null) {
      return const Err<void>(
        ValidationFailure('Choose a valid period', field: 'periodId'),
      );
    }
    // Restricted to the teaching week the editor can actually display: a Sunday
    // entry would validate, then be invisible and unreachable in the UI.
    if (!CalendarDay.teachingWeek.contains(entry.weekday)) {
      return const Err<void>(
        ValidationFailure('Choose a valid day', field: 'weekday'),
      );
    }

    TimetableEntry? clash;
    for (final TimetableEntry other
        in _local.entriesForWeekday(entry.weekday)) {
      if (other.id != entry.id && other.periodId == entry.periodId) {
        clash = other;
        break;
      }
    }

    if (clash != null) {
      return Err<void>(
        ValidationFailure(
          '${clash.subject} ${clash.classGroup} already occupies this period '
          'on ${CalendarDay.longLabel(entry.weekday)}',
          field: 'periodId',
        ),
      );
    }

    return okVoid;
  }

  @override
  Future<Result<void>> upsertEntry(TimetableEntry entry) async {
    final Result<void> validation = validateEntry(entry);
    if (validation.isErr) return validation;

    try {
      final bool isNew = _local.entryById(entry.id) == null;
      await _local.putEntry(entry);
      await _syncQueue.enqueue(
        entityType: SyncEntityTypes.timetableEntry,
        entityId: entry.id,
        operation:
            isNew ? SyncOperationType.create : SyncOperationType.update,
        payload: entry.toJson(),
      );
      return okVoid;
    } on Object catch (error) {
      return Err<void>(CacheFailure('Could not save the class', cause: error));
    }
  }

  @override
  Future<Result<void>> deleteEntry(String entryId) async {
    try {
      await _local.deleteEntry(entryId);
      await _syncQueue.enqueue(
        entityType: SyncEntityTypes.timetableEntry,
        entityId: entryId,
        operation: SyncOperationType.delete,
        payload: <String, dynamic>{'id': entryId},
      );
      return okVoid;
    } on Object catch (error) {
      return Err<void>(CacheFailure('Could not delete the class', cause: error));
    }
  }

  @override
  Future<Result<void>> replacePeriods(List<Period> periods) async {
    if (periods.isEmpty) {
      return const Err<void>(
        ValidationFailure('At least one period is required'),
      );
    }

    try {
      // Captured before the write: `putPeriods` clears the box, so afterwards
      // there is no way to tell which periods the teacher removed, and a removed
      // period would otherwise live on in Firestore forever.
      final Set<String> removedIds = _local
          .periods()
          .map((Period p) => p.id)
          .toSet()
          .difference(periods.map((Period p) => p.id).toSet());

      await _local.putPeriods(periods);

      for (final Period period in periods) {
        await _syncQueue.enqueue(
          entityType: SyncEntityTypes.period,
          entityId: period.id,
          operation: SyncOperationType.update,
          payload: period.toJson(),
        );
      }
      for (final String removedId in removedIds) {
        await _syncQueue.enqueue(
          entityType: SyncEntityTypes.period,
          entityId: removedId,
          operation: SyncOperationType.delete,
          payload: <String, dynamic>{'id': removedId},
        );
      }
      return okVoid;
    } on Object catch (error) {
      return Err<void>(
        CacheFailure('Could not save the bell schedule', cause: error),
      );
    }
  }

  @override
  Future<Result<void>> setSessionStatus({
    required TimetableEntry entry,
    required DateTime date,
    required ClassSessionStatus status,
    String note = '',
  }) async {
    final DateTime day = CalendarDay.dateOnly(date);
    final String sessionId = ClassSession.buildId(day, entry.id);

    try {
      // Reverting to "scheduled" removes the record entirely, which keeps the
      // no-record-means-scheduled invariant and avoids storing a row that says
      // nothing happened.
      if (status == ClassSessionStatus.scheduled) {
        await _local.deleteSession(sessionId);
        await _syncQueue.enqueue(
          entityType: SyncEntityTypes.classSession,
          entityId: sessionId,
          operation: SyncOperationType.delete,
          payload: <String, dynamic>{'id': sessionId},
        );
        return okVoid;
      }

      final bool isNew = _local.sessionById(sessionId) == null;
      final ClassSession session = ClassSession(
        id: sessionId,
        entryId: entry.id,
        date: day,
        status: status,
        // Truncated to milliseconds because that is all Hive's DateTime framing
        // preserves; storing microseconds would make a value change on reload.
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          _clock.now().millisecondsSinceEpoch,
        ),
        note: note,
      );

      await _local.putSession(session);
      await _syncQueue.enqueue(
        entityType: SyncEntityTypes.classSession,
        entityId: sessionId,
        operation:
            isNew ? SyncOperationType.create : SyncOperationType.update,
        payload: session.toJson(),
      );
      return okVoid;
    } on Object catch (error) {
      return Err<void>(
        CacheFailure('Could not record the class', cause: error),
      );
    }
  }

  @override
  Future<Result<int>> clearAllData() async {
    try {
      int removed = 0;

      for (final TimetableEntry entry in _local.allEntries()) {
        await _local.deleteEntry(entry.id);
        await _syncQueue.enqueue(
          entityType: SyncEntityTypes.timetableEntry,
          entityId: entry.id,
          operation: SyncOperationType.delete,
          payload: <String, dynamic>{'id': entry.id},
        );
        removed++;
      }

      for (final ClassSession session in _local.allSessions()) {
        await _local.deleteSession(session.id);
        await _syncQueue.enqueue(
          entityType: SyncEntityTypes.classSession,
          entityId: session.id,
          operation: SyncOperationType.delete,
          payload: <String, dynamic>{'id': session.id},
        );
        removed++;
      }

      return Ok<int>(removed);
    } on Object catch (error) {
      return Err<int>(CacheFailure('Could not clear the data', cause: error));
    }
  }

  @override
  Stream<void> watchChanges() => _local.watchChanges();

  @override
  List<String> subjects() => _subjects.subjects();

  @override
  Future<Result<String>> addSubject(String name) async {
    try {
      final String? canonical = await _subjects.add(name);
      if (canonical == null) {
        return const Err<String>(
          ValidationFailure('Subject name is required', field: 'subject'),
        );
      }
      return Ok<String>(canonical);
    } on Object catch (error) {
      return Err<String>(
        CacheFailure('Could not add the subject', cause: error),
      );
    }
  }

  @override
  Future<Result<void>> removeSubject(String name) async {
    try {
      // `remove` reports false for two different reasons. Distinguished here so
      // a double-tap on the remove button does not claim the list is about to be
      // emptied when there are seventeen subjects left.
      final String needle = name.trim().toLowerCase();
      final bool wasPresent =
          _subjects.subjects().any((String s) => s.toLowerCase() == needle);

      final bool removed = await _subjects.remove(name);
      if (!removed) {
        return Err<void>(
          ValidationFailure(
            wasPresent
                ? 'Keep at least one subject in the list'
                : 'That subject is not in the list',
            field: 'subject',
          ),
        );
      }
      return okVoid;
    } on Object catch (error) {
      return Err<void>(
        CacheFailure('Could not remove the subject', cause: error),
      );
    }
  }

  @override
  Future<Result<void>> restoreDefaultSubjects() async {
    try {
      await _subjects.restoreDefaults();
      return okVoid;
    } on Object catch (error) {
      return Err<void>(
        CacheFailure('Could not restore the subject list', cause: error),
      );
    }
  }

  @override
  Stream<void> watchSubjects() => _subjects.watchChanges();
}
