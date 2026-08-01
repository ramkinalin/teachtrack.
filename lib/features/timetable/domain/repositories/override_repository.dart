import '../../../../core/utils/result.dart';
import '../entities/schedule_override.dart';

/// CRUD for schedule overrides.
///
/// Separate from [TimetableRepository] on purpose: that one *reads* overrides to
/// decide what a given day looks like, while this one is what an editor writes
/// through. Keeping them apart stops the day-resolution path from growing an
/// editing surface it never uses.
abstract interface class OverrideRepository {
  /// Every override, soonest first.
  List<ScheduleOverride> all();

  /// Overrides that have not finished yet, soonest first.
  List<ScheduleOverride> upcoming({required DateTime from});

  ScheduleOverride? byId(String id);

  /// The override covering [date], or `null` if the normal timetable applies.
  ScheduleOverride? covering(DateTime date);

  /// Rejects a blank name, an inverted range, a range overlapping another
  /// override, slots outside the range, slots on a holiday, and impossible times.
  Result<void> validate(ScheduleOverride override);

  Future<Result<void>> upsert(ScheduleOverride override);

  Future<Result<void>> delete(String id);

  Stream<void> watchChanges();
}
