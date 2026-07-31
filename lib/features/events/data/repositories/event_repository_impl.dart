import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/services/sync/sync_queue_service.dart';
import '../../../../core/utils/clock.dart';
import '../../../../core/utils/day_time.dart';
import '../../../../core/utils/result.dart';
import '../../../../shared/models/pending_operation.dart';
import '../../domain/entities/school_event.dart';
import '../../domain/repositories/event_repository.dart';
import '../local/event_local_data_source.dart';

/// Local-first event repository: commit to Hive, then append to the outbox.
class EventRepositoryImpl implements EventRepository {
  EventRepositoryImpl({
    required EventLocalDataSource local,
    required SyncQueueService syncQueue,
    Clock clock = const Clock(),
  })  : _local = local,
        _syncQueue = syncQueue,
        _clock = clock;

  final EventLocalDataSource _local;
  final SyncQueueService _syncQueue;
  final Clock _clock;

  @override
  List<SchoolEvent> upcoming({required DateTime from, int days = 60}) {
    final DateTime start = CalendarDay.dateOnly(from);
    // Constructed rather than added so a DST boundary cannot shift the window.
    final DateTime end = DateTime(start.year, start.month, start.day + days);

    final List<SchoolEvent> events = _local
        .all()
        .where(
          (SchoolEvent e) =>
              !e.date.isBefore(start) && e.date.isBefore(end),
        )
        .toList()
      ..sort(_byDateThenTime);

    return events;
  }

  @override
  List<SchoolEvent> forDate(DateTime date) {
    final DateTime day = CalendarDay.dateOnly(date);
    final List<SchoolEvent> events = _local
        .all()
        .where((SchoolEvent e) => CalendarDay.isSameDay(e.date, day))
        .toList()
      ..sort(_byDateThenTime);
    return events;
  }

  @override
  List<SchoolEvent> all() {
    final List<SchoolEvent> events = _local.all().toList()
      ..sort((SchoolEvent a, SchoolEvent b) => b.date.compareTo(a.date));
    return events;
  }

  @override
  SchoolEvent? byId(String id) => _local.byId(id);

  @override
  Result<void> validate(SchoolEvent event) {
    if (event.title.trim().isEmpty) {
      return const Err<void>(
        ValidationFailure('Give the event a name', field: 'title'),
      );
    }

    final int? start = event.startMinute;
    final int? end = event.endMinute;

    if (start != null && (start < 0 || start >= DayTime.minutesPerDay)) {
      return const Err<void>(
        ValidationFailure('Start time is not valid', field: 'startMinute'),
      );
    }
    if (end != null && start == null) {
      return const Err<void>(
        ValidationFailure(
          'Set a start time before an end time',
          field: 'startMinute',
        ),
      );
    }
    if (end != null && end >= DayTime.minutesPerDay) {
      return const Err<void>(
        ValidationFailure('End time is not valid', field: 'endMinute'),
      );
    }
    if (start != null && end != null && end <= start) {
      return const Err<void>(
        ValidationFailure(
          'End time must be after the start time',
          field: 'endMinute',
        ),
      );
    }
    if (event.reminderLeadMinutes.any((int lead) => lead < 0)) {
      return const Err<void>(
        ValidationFailure(
          'A reminder cannot be after the event',
          field: 'reminderLeadMinutes',
        ),
      );
    }

    return okVoid;
  }

  @override
  Future<Result<void>> upsert(SchoolEvent event) async {
    final Result<void> validation = validate(event);
    if (validation.isErr) return validation;

    try {
      final bool isNew = _local.byId(event.id) == null;
      final SchoolEvent stored = event.copyWith(
        date: CalendarDay.dateOnly(event.date),
        title: event.title.trim(),
        // Truncated to milliseconds, which is all Hive's DateTime framing keeps.
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          _clock.now().millisecondsSinceEpoch,
        ),
      );

      await _local.put(stored);
      await _syncQueue.enqueue(
        entityType: SyncEntityTypes.schoolEvent,
        entityId: stored.id,
        operation:
            isNew ? SyncOperationType.create : SyncOperationType.update,
        payload: stored.toJson(),
      );
      return okVoid;
    } on Object catch (error) {
      return Err<void>(CacheFailure('Could not save the event', cause: error));
    }
  }

  @override
  Future<Result<void>> delete(String id) async {
    // Deleting something that isn't there would otherwise spend a remote write
    // on a no-op.
    if (_local.byId(id) == null) return okVoid;

    try {
      await _local.delete(id);
      await _syncQueue.enqueue(
        entityType: SyncEntityTypes.schoolEvent,
        entityId: id,
        operation: SyncOperationType.delete,
        payload: <String, dynamic>{'id': id},
      );
      return okVoid;
    } on Object catch (error) {
      return Err<void>(CacheFailure('Could not delete the event', cause: error));
    }
  }

  @override
  Stream<void> watchChanges() => _local.watchChanges();

  /// Chronological, with all-day events first on any given date.
  static int _byDateThenTime(SchoolEvent a, SchoolEvent b) {
    final int byDate = a.date.compareTo(b.date);
    if (byDate != 0) return byDate;
    return (a.startMinute ?? -1).compareTo(b.startMinute ?? -1);
  }
}
