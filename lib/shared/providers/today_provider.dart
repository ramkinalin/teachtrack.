import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/day_time.dart';
import 'core_providers.dart';

/// Today's date, self-invalidating just after midnight.
///
/// Shared rather than owned by any one feature: "what day is it" is not a
/// timetable concern, and every feature that shows dated data needs the same
/// answer. Without the rollover, an app left open overnight keeps showing
/// yesterday — and worse, records against it.
final todayProvider = Provider<DateTime>((ref) {
  final DateTime now = ref.watch(clockProvider).now();
  final DateTime today = CalendarDay.dateOnly(now);

  // Constructed rather than `add(Duration(days: 1))` so a DST transition cannot
  // land the boundary an hour early or late.
  final DateTime nextMidnight = DateTime(today.year, today.month, today.day + 1);
  final Timer rollover = Timer(
    nextMidnight.difference(now) + const Duration(seconds: 1),
    ref.invalidateSelf,
  );
  ref.onDispose(rollover.cancel);

  return today;
});
