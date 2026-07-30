import '../../../core/utils/day_time.dart';
import 'entities/class_session.dart';
import 'entities/scheduled_class.dart';

/// What a teacher needs to know at a glance, derived for a given instant.
class ScheduleSnapshot {
  const ScheduleSnapshot({
    this.current,
    this.next,
    this.remainingInCurrent,
    this.untilNext,
  });

  /// The class happening right now, if any.
  final ScheduledClass? current;

  /// The next class still to come today, if any.
  final ScheduledClass? next;

  /// Time left in [current].
  final Duration? remainingInCurrent;

  /// Time until [next] starts.
  final Duration? untilNext;

  bool get isFreePeriod => current == null;
  bool get dayIsOver => current == null && next == null;

  String? get remainingLabel => remainingInCurrent == null
      ? null
      : DayTime.formatRemaining(remainingInCurrent!);

  String? get untilNextLabel =>
      untilNext == null ? null : DayTime.formatRemaining(untilNext!);

  // Value equality so `select`-based watchers only rebuild on a real change.
  @override
  bool operator ==(Object other) =>
      other is ScheduleSnapshot &&
      other.current?.entry.id == current?.entry.id &&
      other.next?.entry.id == next?.entry.id &&
      other.remainingInCurrent == remainingInCurrent &&
      other.untilNext == untilNext;

  @override
  int get hashCode => Object.hash(
        current?.entry.id,
        next?.entry.id,
        remainingInCurrent,
        untilNext,
      );
}

/// Pure resolution of "what now, what next" from a day's schedule.
///
/// Kept free of Riverpod, Flutter and `DateTime.now()` so the boundary cases —
/// the minute a period ends, gaps between periods, the end of the day — are
/// testable without waiting for a clock.
abstract final class ScheduleResolver {
  static ScheduleSnapshot resolve(
    List<ScheduledClass> schedule,
    DateTime now,
  ) {
    if (schedule.isEmpty) return const ScheduleSnapshot();

    final List<ScheduledClass> ordered = <ScheduledClass>[...schedule]..sort(
        (ScheduledClass a, ScheduledClass b) =>
            a.period.startMinute.compareTo(b.period.startMinute),
      );

    final int minuteNow = DayTime.fromDateTime(now);

    ScheduledClass? current;
    ScheduledClass? next;

    for (final ScheduledClass item in ordered) {
      if (item.period.containsMinute(minuteNow)) {
        current = item;
        continue;
      }
      // First slot starting later today wins, breaks included: a teacher wants
      // to know a break is next just as much as a lesson.
      if (next == null && item.period.isAfter(minuteNow)) {
        next = item;
      }
    }

    return ScheduleSnapshot(
      current: current,
      next: next,
      remainingInCurrent: current == null
          ? null
          : Duration(minutes: current.period.endMinute - minuteNow) -
              Duration(seconds: now.second),
      untilNext: next == null
          ? null
          : Duration(minutes: next.period.startMinute - minuteNow) -
              Duration(seconds: now.second),
    );
  }

  /// Lessons still untouched by [minuteNow], for a gentle end-of-day nudge.
  ///
  /// Takes minutes-since-midnight rather than a `DateTime` so callers cannot be
  /// tempted to reconstruct an instant by adding minutes to a local midnight,
  /// which is wrong across a DST transition.
  static List<ScheduledClass> unmarkedPast(
    List<ScheduledClass> schedule,
    int minuteNow,
  ) {
    return schedule
        .where(
          (ScheduledClass item) =>
              item.isActionable &&
              item.status == ClassSessionStatus.scheduled &&
              item.period.isBefore(minuteNow),
        )
        .toList(growable: false);
  }
}
