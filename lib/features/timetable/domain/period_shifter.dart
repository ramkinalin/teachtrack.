import '../../../core/utils/day_time.dart';
import 'entities/period.dart';

/// Adjusts a whole bell schedule to a new start time.
///
/// Schools keep the same period lengths and gaps but start at different times, so
/// setup asks one question — when does first period start — instead of making a
/// teacher retype ten pairs of times. Every period is moved by the same offset,
/// which preserves durations, breaks and the gaps between them exactly.
abstract final class PeriodShifter {
  /// Returns [periods] moved so the earliest one begins at [newStartMinute], or
  /// `null` if the shift is impossible.
  ///
  /// Refusal is `null` rather than the unchanged input on purpose: an earlier
  /// version returned the input, and the caller could not tell success from
  /// refusal, so an impossible time was saved and reported as if it had worked.
  static List<Period>? shiftTo(List<Period> periods, int newStartMinute) {
    if (periods.isEmpty) return null;

    final List<Period> ordered = <Period>[...periods]
      ..sort((Period a, Period b) => a.sortOrder.compareTo(b.sortOrder));

    int earliest = ordered.first.startMinute;
    int latest = ordered.first.endMinute;
    for (final Period period in ordered) {
      if (period.startMinute < earliest) earliest = period.startMinute;
      if (period.endMinute > latest) latest = period.endMinute;
    }

    final int offset = newStartMinute - earliest;
    if (offset == 0) return ordered;

    // A school day may not wrap around midnight.
    if (earliest + offset < 0 || latest + offset > DayTime.minutesPerDay) {
      return null;
    }

    return ordered
        .map(
          (Period period) => period.copyWith(
            startMinute: period.startMinute + offset,
            endMinute: period.endMinute + offset,
          ),
        )
        .toList(growable: false);
  }

  /// The start of the earliest period, for pre-filling the setup time picker.
  static int? firstStartMinute(List<Period> periods) {
    if (periods.isEmpty) return null;
    int earliest = periods.first.startMinute;
    for (final Period period in periods) {
      if (period.startMinute < earliest) earliest = period.startMinute;
    }
    return earliest;
  }
}
