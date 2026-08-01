import '../../../../core/utils/result.dart';
import '../entities/class_session.dart';
import '../entities/period.dart';
import '../entities/schedule_override.dart';
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

  /// What is happening on [date].
  ///
  /// A [ScheduleOverride] covering the date replaces the weekly pattern: a
  /// holiday yields an empty list, and an exam or special schedule yields its
  /// sittings. Otherwise it is the date's weekday entries joined with their
  /// periods and any recorded session, ordered by period start time.
  List<ScheduledClass> scheduleFor(DateTime date);

  /// The override covering [date], so the UI can say why the day looks unusual.
  /// `null` when the normal timetable applies.
  ScheduleOverride? overrideFor(DateTime date);

  /// Rejects an entry that would occupy a slot another entry already holds.
  Result<void> validateEntry(TimetableEntry entry);

  Future<Result<void>> upsertEntry(TimetableEntry entry);

  Future<Result<void>> deleteEntry(String entryId);

  Future<Result<void>> replacePeriods(List<Period> periods);

  /// Records what happened to one class on one date.
  ///
  /// A `null` [note] leaves any existing note untouched — changing a status must
  /// never silently discard what the teacher wrote.
  ///
  /// The record is removed only when the status is
  /// [ClassSessionStatus.scheduled] *and* there is no note, preserving the
  /// "no record means scheduled" invariant while still allowing a note to stand
  /// on its own.
  Future<Result<void>> setSessionStatus({
    required TimetableEntry entry,
    required DateTime date,
    required ClassSessionStatus status,
    String? note,
  });

  /// Writes a note against one class on one date, keeping its current status.
  ///
  /// Delegates to [setSessionStatus] so there is exactly one place that decides
  /// when a record is created or removed.
  Future<Result<void>> setSessionNote({
    required TimetableEntry entry,
    required DateTime date,
    required String note,
  });

  /// Removes every entry and session, queueing a delete for each.
  ///
  /// Goes through the outbox rather than clearing the boxes directly: a bare
  /// clear would leave queued creates for records that no longer exist, and once
  /// a backend is wired up the next sync would push the deleted data upstream.
  ///
  /// The bell schedule and subject list survive — they are school configuration,
  /// not the teacher's own data.
  Future<Result<int>> clearAllData();

  /// Emits whenever any timetable data changes locally.
  Stream<void> watchChanges();

  // --- Subject list ----------------------------------------------------------
  //
  // Subjects are an input aid for the entry form, not a relational key: an entry
  // stores its subject as text, so editing this list can never orphan a class.

  List<String> subjects();

  /// Returns the canonical stored name, which may differ in case from [name]
  /// when a variant spelling already exists.
  Future<Result<String>> addSubject(String name);

  Future<Result<void>> removeSubject(String name);

  Future<Result<void>> restoreDefaultSubjects();

  Stream<void> watchSubjects();
}
