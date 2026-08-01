import 'class_session.dart';
import 'period.dart';
import 'schedule_override.dart';
import 'timetable_entry.dart';

/// A timetable entry resolved against a specific date.
///
/// Joins the recurring [entry], its [period] times and the optional [session]
/// recording what happened. Purely derived — never stored.
///
/// Also carries days that come from a [ScheduleOverride] instead of the weekly
/// pattern: exam sittings arrive as this same type with a synthesised entry and
/// period, so the day list, the current/next card, the countdown and one-tap
/// marking all keep working without a presentation-layer rewrite. Being a derived
/// view type is what makes that legitimate rather than a fudge.
class ScheduledClass {
  const ScheduledClass({
    required this.entry,
    required this.period,
    required this.date,
    this.session,
    this.slot,
  });

  final TimetableEntry entry;
  final Period period;

  /// Date-only, local.
  final DateTime date;

  /// `null` means nothing has been recorded, i.e. still scheduled.
  final ClassSession? session;

  /// Set when this came from an override rather than the weekly timetable.
  ///
  /// The kind of override is not repeated here: the synthesised period's label
  /// already carries it, and a second copy would be one more thing to keep in
  /// step.
  final OverrideSlot? slot;

  ClassSessionStatus get status => session?.status ?? ClassSessionStatus.scheduled;

  bool get isCompleted => status == ClassSessionStatus.completed;
  bool get isCancelled => status == ClassSessionStatus.cancelled;

  bool get isFromOverride => slot != null;

  /// This teacher is on duty for the sitting.
  bool get isInvigilating => slot?.isInvigilating ?? false;

  /// The sitting is of this teacher's own subject.
  bool get isMySubject => slot?.isMySubject ?? false;

  /// Whether marking this makes sense.
  ///
  /// Breaks never do. Neither does a sitting that is somebody else's duty and
  /// somebody else's subject — it appears so the teacher knows the hall is in
  /// use, but nudging them to tick it off would be asking them to account for a
  /// paper that was nothing to do with them.
  bool get isActionable {
    if (period.isBreak) return false;
    if (slot == null) return true;
    return isInvigilating || isMySubject;
  }

  String get sessionId => ClassSession.buildId(date, entry.id);

  // Note: no `startsAt`/`endsAt` helpers. Adding minute offsets to a local
  // midnight is wrong across a DST transition, and nothing needs absolute
  // instants — comparisons happen in minute-of-day space instead.

  @override
  String toString() =>
      'ScheduledClass(${entry.subject} ${entry.classGroup}, '
      '${period.timeRangeLabel}, ${status.name}'
      '${isFromOverride ? ', override' : ''})';
}
