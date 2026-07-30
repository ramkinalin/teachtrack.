import 'class_session.dart';
import 'period.dart';
import 'timetable_entry.dart';

/// A timetable entry resolved against a specific date.
///
/// Joins the recurring [entry], its [period] times and the optional [session]
/// recording what happened. Purely derived — never stored.
class ScheduledClass {
  const ScheduledClass({
    required this.entry,
    required this.period,
    required this.date,
    this.session,
  });

  final TimetableEntry entry;
  final Period period;

  /// Date-only, local.
  final DateTime date;

  /// `null` means nothing has been recorded, i.e. still scheduled.
  final ClassSession? session;

  ClassSessionStatus get status => session?.status ?? ClassSessionStatus.scheduled;

  bool get isCompleted => status == ClassSessionStatus.completed;
  bool get isCancelled => status == ClassSessionStatus.cancelled;

  /// Only real lessons can be marked complete — breaks cannot.
  bool get isActionable => !period.isBreak;

  String get sessionId => ClassSession.buildId(date, entry.id);

  // Note: no `startsAt`/`endsAt` helpers. Adding minute offsets to a local
  // midnight is wrong across a DST transition, and nothing needs absolute
  // instants — comparisons happen in minute-of-day space instead.

  @override
  String toString() =>
      'ScheduledClass(${entry.subject} ${entry.classGroup}, '
      '${period.timeRangeLabel}, ${status.name})';
}
