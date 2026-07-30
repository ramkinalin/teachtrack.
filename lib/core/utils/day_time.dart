/// Time-of-day and calendar-day helpers.
///
/// Times are stored as minutes since midnight (`0..1439`) rather than `DateTime`
/// or `TimeOfDay`. They serialise as a single int, compare with `<`, survive
/// timezone changes, and carry no accidental date component.
abstract final class DayTime {
  static const int minutesPerDay = 24 * 60;

  static int fromDateTime(DateTime time) => time.hour * 60 + time.minute;

  /// `08:45`, always zero-padded and 24-hour so period lists align visually.
  static String format(int minuteOfDay) {
    // Clamped to 23:59 rather than 1440, which would render as "24:00".
    final int clamped = minuteOfDay.clamp(0, minutesPerDay - 1);
    final String hh = (clamped ~/ 60).toString().padLeft(2, '0');
    final String mm = (clamped % 60).toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  static String formatRange(int startMinute, int endMinute) =>
      '${format(startMinute)} – ${format(endMinute)}';

  /// Human-readable duration for countdowns: `4h 05m`, `12m`, `45s`.
  static String formatRemaining(Duration remaining) {
    if (remaining.isNegative) return '0m';
    if (remaining.inMinutes < 1) return '${remaining.inSeconds}s';
    if (remaining.inHours < 1) return '${remaining.inMinutes}m';
    final int minutes = remaining.inMinutes.remainder(60);
    return '${remaining.inHours}h ${minutes.toString().padLeft(2, '0')}m';
  }
}

/// Calendar-day helpers. A "day" is always local: a teacher's Monday is the
/// Monday they are standing in, never UTC.
abstract final class CalendarDay {
  static DateTime dateOnly(DateTime time) =>
      DateTime(time.year, time.month, time.day);

  /// Stable `2026-07-30` key, used to build deterministic session ids.
  static String key(DateTime time) {
    final String month = time.month.toString().padLeft(2, '0');
    final String day = time.day.toString().padLeft(2, '0');
    return '${time.year}-$month-$day';
  }

  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// `DateTime.monday`..`DateTime.sunday` (1..7).
  static const List<int> teachingWeek = <int>[
    DateTime.monday,
    DateTime.tuesday,
    DateTime.wednesday,
    DateTime.thursday,
    DateTime.friday,
    DateTime.saturday,
  ];

  static const Map<int, String> weekdayShortLabels = <int, String>{
    DateTime.monday: 'Mon',
    DateTime.tuesday: 'Tue',
    DateTime.wednesday: 'Wed',
    DateTime.thursday: 'Thu',
    DateTime.friday: 'Fri',
    DateTime.saturday: 'Sat',
    DateTime.sunday: 'Sun',
  };

  static const Map<int, String> weekdayLongLabels = <int, String>{
    DateTime.monday: 'Monday',
    DateTime.tuesday: 'Tuesday',
    DateTime.wednesday: 'Wednesday',
    DateTime.thursday: 'Thursday',
    DateTime.friday: 'Friday',
    DateTime.saturday: 'Saturday',
    DateTime.sunday: 'Sunday',
  };

  static String shortLabel(int weekday) =>
      weekdayShortLabels[weekday] ?? 'Day $weekday';

  static String longLabel(int weekday) =>
      weekdayLongLabels[weekday] ?? 'Day $weekday';
}
