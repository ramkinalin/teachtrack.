import '../../../../core/utils/result.dart';
import '../entities/class_session.dart';
import '../entities/period.dart';
import '../entities/scheduled_class.dart';
import '../entities/timetable_entry.dart';

/// Timetable data access.
///
/// Reads are **synchronous** by design: everything is already in an open Hive
/// box, so a screen can render real content on its first frame instead of a
/// spinner. Only writes are async, and even they complete as soon as the local
/// commit lands — the remote push happens later via the outbox.
abstract interface class TimetableRepository {
  List<Period> periods();

  Period? periodById(String id);

  List<TimetableEntry> allEntries();

  List<TimetableEntry> entriesForWeekday(int weekday);

  TimetableEntry? entryById(String id);

  /// Entries for [date]'s weekday, joined with their periods and any recorded
  /// session, ordered by period start time.
  List<ScheduledClass> scheduleFor(DateTime date);

  /// Rejects an entry that would occupy a slot another entry already holds.
  Result<void> validateEntry(TimetableEntry entry);

  Future<Result<void>> upsertEntry(TimetableEntry entry);

  Future<Result<void>> deleteEntry(String entryId);

  Future<Result<void>> replacePeriods(List<Period> periods);

  /// Records what happened to one class on one date, or clears the record when
  /// [status] is [ClassSessionStatus.scheduled].
  Future<Result<void>> setSessionStatus({
    required TimetableEntry entry,
    required DateTime date,
    required ClassSessionStatus status,
    String note,
  });

  /// Emits whenever any timetable data changes locally.
  Stream<void> watchChanges();
}
