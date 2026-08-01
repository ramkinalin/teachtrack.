import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/services/sync/sync_queue_service.dart';
import '../../../../core/utils/clock.dart';
import '../../../../core/utils/day_time.dart';
import '../../../../core/utils/result.dart';
import '../../../../shared/models/pending_operation.dart';
import '../../domain/entities/class_session.dart';
import '../../domain/entities/period.dart';
import '../../domain/entities/schedule_override.dart';
import '../../domain/entities/scheduled_class.dart';
import '../../domain/entities/timetable_entry.dart';
import '../../domain/repositories/timetable_repository.dart';
import '../local/override_local_data_source.dart';
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
    OverrideLocalDataSource? overrides,
    Clock clock = const Clock(),
  })  : _local = local,
        _subjects = subjects,
        _syncQueue = syncQueue,
        _overrides = overrides,
        _clock = clock;

  final TimetableLocalDataSource _local;
  final SubjectStore _subjects;

  /// Optional so existing tests and any caller that only needs the weekly
  /// pattern keep working; when absent, every day falls back to the timetable.
  final OverrideLocalDataSource? _overrides;
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
  ScheduleOverride? overrideFor(DateTime date) => _overrides?.covering(date);

  @override
  List<ScheduledClass> scheduleFor(DateTime date) {
    final DateTime day = CalendarDay.dateOnly(date);

    // Overrides win over the weekly pattern. A holiday deliberately yields an
    // empty day rather than the normal timetable with everything cancelled.
    final ScheduleOverride? override = _overrides?.covering(day);
    if (override != null) {
      return override.isHoliday
          ? const <ScheduledClass>[]
          : _scheduleFromOverride(override, day);
    }

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

  /// Turns an override's sittings for one date into the day view.
  ///
  /// The entry and period are synthesised, not stored: `ScheduledClass` is a
  /// derived type, so giving a sitting the same shape as a lesson is what lets
  /// the whole existing day UI — ordering, countdown, one-tap marking — work
  /// unchanged. Ids are prefixed so a sitting's session record can never collide
  /// with a lesson's.
  List<ScheduledClass> _scheduleFromOverride(
    ScheduleOverride override,
    DateTime day,
  ) {
    final List<OverrideSlot> slots = override.slotsOn(day);

    return <ScheduledClass>[
      for (int i = 0; i < slots.length; i++)
        () {
          final OverrideSlot slot = slots[i];
          final String entryId = 'slot:${slot.id}';

          return ScheduledClass(
            entry: TimetableEntry(
              id: entryId,
              weekday: day.weekday,
              periodId: 'slot:${slot.id}',
              subject: slot.title,
              classGroup: slot.classGroup,
              room: slot.location,
              notes: slot.notes,
              teacherId: override.teacherId,
            ),
            period: Period(
              id: 'slot:${slot.id}',
              label: override.kind.label,
              startMinute: slot.startMinute,
              // A sitting with no end time is shown as a nominal hour so it
              // occupies the day sensibly and the countdown has something to
              // count down to.
              endMinute: slot.endMinute ?? (slot.startMinute + 60),
              sortOrder: i,
            ),
            date: day,
            session: _local.sessionById(ClassSession.buildId(day, entryId)),
            slot: slot,
          );
        }(),
    ];
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
  Future<Result<void>> setSessionNote({
    required TimetableEntry entry,
    required DateTime date,
    required String note,
  }) {
    final ClassSession? existing = _local
        .sessionById(ClassSession.buildId(CalendarDay.dateOnly(date), entry.id));

    return setSessionStatus(
      entry: entry,
      date: date,
      status: existing?.status ?? ClassSessionStatus.scheduled,
      note: note,
    );
  }

  @override
  Future<Result<void>> setSessionStatus({
    required TimetableEntry entry,
    required DateTime date,
    required ClassSessionStatus status,
    String? note,
  }) async {
    final DateTime day = CalendarDay.dateOnly(date);
    final String sessionId = ClassSession.buildId(day, entry.id);
    final ClassSession? existing = _local.sessionById(sessionId);

    // A null note means "leave it alone", so changing a status never discards
    // what the teacher wrote.
    final String resolvedNote = (note ?? existing?.note ?? '').trim();

    try {
      // Nothing happened and nothing was written, so store nothing: this is what
      // keeps a normal week at zero writes. A note alone is enough to keep the
      // record alive.
      if (status == ClassSessionStatus.scheduled && resolvedNote.isEmpty) {
        await _local.deleteSession(sessionId);
        await _syncQueue.enqueue(
          entityType: SyncEntityTypes.classSession,
          entityId: sessionId,
          operation: SyncOperationType.delete,
          payload: <String, dynamic>{'id': sessionId},
        );
        return okVoid;
      }

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
        note: resolvedNote,
      );

      await _local.putSession(session);
      await _syncQueue.enqueue(
        entityType: SyncEntityTypes.classSession,
        entityId: sessionId,
        operation: existing == null
            ? SyncOperationType.create
            : SyncOperationType.update,
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

      // Overrides go too. Leaving them would resurrect exam sittings on top of an
      // otherwise wiped timetable, which is a confusing state to hand back.
      final OverrideLocalDataSource? overrides = _overrides;
      if (overrides != null) {
        for (final ScheduleOverride override in overrides.all()) {
          await overrides.delete(override.id);
          await _syncQueue.enqueue(
            entityType: SyncEntityTypes.scheduleOverride,
            entityId: override.id,
            operation: SyncOperationType.delete,
            payload: <String, dynamic>{'id': override.id},
          );
          removed++;
        }
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
