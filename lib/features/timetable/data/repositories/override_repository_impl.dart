import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/services/sync/sync_queue_service.dart';
import '../../../../core/utils/clock.dart';
import '../../../../core/utils/day_time.dart';
import '../../../../core/utils/result.dart';
import '../../../../shared/models/pending_operation.dart';
import '../../domain/entities/schedule_override.dart';
import '../../domain/repositories/override_repository.dart';
import '../local/override_local_data_source.dart';

class OverrideRepositoryImpl implements OverrideRepository {
  OverrideRepositoryImpl({
    required OverrideLocalDataSource local,
    required SyncQueueService syncQueue,
    Clock clock = const Clock(),
  })  : _local = local,
        _syncQueue = syncQueue,
        _clock = clock;

  final OverrideLocalDataSource _local;
  final SyncQueueService _syncQueue;
  final Clock _clock;

  @override
  List<ScheduleOverride> all() => _local.all();

  @override
  List<ScheduleOverride> upcoming({required DateTime from}) {
    final DateTime day = CalendarDay.dateOnly(from);
    return _local
        .all()
        .where((ScheduleOverride o) => !o.endDate.isBefore(day))
        .toList(growable: false);
  }

  @override
  ScheduleOverride? byId(String id) => _local.byId(id);

  @override
  ScheduleOverride? covering(DateTime date) => _local.covering(date);

  @override
  Result<void> validate(ScheduleOverride override) {
    if (override.name.trim().isEmpty) {
      return const Err<void>(
        ValidationFailure('Give it a name', field: 'name'),
      );
    }
    if (override.endDate.isBefore(override.startDate)) {
      return const Err<void>(
        ValidationFailure(
          'The end date cannot be before the start date',
          field: 'endDate',
        ),
      );
    }

    // Overlaps are refused rather than resolved: two schedules claiming the same
    // day has no correct answer, and silently picking one would be worse than
    // making the teacher choose.
    for (final ScheduleOverride other in _local.all()) {
      if (other.id == override.id) continue;
      if (override.overlaps(other)) {
        return Err<void>(
          ValidationFailure(
            '"${other.name}" already covers ${other.rangeLabel}',
            field: 'startDate',
          ),
        );
      }
    }

    if (!override.kind.allowsSlots && override.slots.isNotEmpty) {
      return const Err<void>(
        ValidationFailure(
          'A holiday has no sittings — remove them or change the type',
          field: 'slots',
        ),
      );
    }

    final Set<String> seenSlotIds = <String>{};

    for (final OverrideSlot slot in override.slots) {
      // Duplicate ids would synthesise the same entry id, and therefore the same
      // session id — so marking one sitting complete would mark both.
      if (!seenSlotIds.add(slot.id)) {
        return const Err<void>(
          ValidationFailure('Two sittings share an id', field: 'slots'),
        );
      }
      if (slot.title.trim().isEmpty) {
        return const Err<void>(
          ValidationFailure('Every sitting needs a name', field: 'slots'),
        );
      }
      if (!override.covers(slot.date)) {
        return Err<void>(
          ValidationFailure(
            '"${slot.title}" falls outside ${override.rangeLabel}',
            field: 'slots',
          ),
        );
      }
      if (slot.startMinute < 0 ||
          slot.startMinute >= DayTime.minutesPerDay) {
        return const Err<void>(
          ValidationFailure('A sitting has an invalid start time',
              field: 'slots'),
        );
      }
      final int? end = slot.endMinute;
      if (end != null &&
          (end <= slot.startMinute || end >= DayTime.minutesPerDay)) {
        return Err<void>(
          ValidationFailure(
            '"${slot.title}" must end after it starts',
            field: 'slots',
          ),
        );
      }
    }

    return okVoid;
  }

  @override
  Future<Result<void>> upsert(ScheduleOverride override) async {
    final ScheduleOverride normalised = override.copyWith(
      name: override.name.trim(),
      startDate: CalendarDay.dateOnly(override.startDate),
      endDate: CalendarDay.dateOnly(override.endDate),
      slots: override.slots
          .map((OverrideSlot s) =>
              s.copyWith(date: CalendarDay.dateOnly(s.date)))
          .toList(growable: false),
    );

    // Validated after normalising, so a date carrying a time component cannot
    // fail a range check it should have passed.
    final Result<void> validation = validate(normalised);
    if (validation.isErr) return validation;

    try {
      final bool isNew = _local.byId(normalised.id) == null;
      final ScheduleOverride stored = normalised.copyWith(
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          _clock.now().millisecondsSinceEpoch,
        ),
      );

      await _local.put(stored);
      await _syncQueue.enqueue(
        entityType: SyncEntityTypes.scheduleOverride,
        entityId: stored.id,
        operation:
            isNew ? SyncOperationType.create : SyncOperationType.update,
        payload: stored.toJson(),
      );
      return okVoid;
    } on Object catch (error) {
      return Err<void>(
        CacheFailure('Could not save the schedule', cause: error),
      );
    }
  }

  @override
  Future<Result<void>> delete(String id) async {
    if (_local.byId(id) == null) return okVoid;

    try {
      await _local.delete(id);
      await _syncQueue.enqueue(
        entityType: SyncEntityTypes.scheduleOverride,
        entityId: id,
        operation: SyncOperationType.delete,
        payload: <String, dynamic>{'id': id},
      );
      return okVoid;
    } on Object catch (error) {
      return Err<void>(
        CacheFailure('Could not delete the schedule', cause: error),
      );
    }
  }

  @override
  Stream<void> watchChanges() => _local.watchChanges();
}
