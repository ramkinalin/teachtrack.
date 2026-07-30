import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/clock.dart';
import '../../../../core/utils/day_time.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../data/local/timetable_local_data_source.dart';
import '../../data/repositories/timetable_repository_impl.dart';
import '../../domain/entities/period.dart';
import '../../domain/entities/scheduled_class.dart';
import '../../domain/entities/timetable_entry.dart';
import '../../domain/repositories/timetable_repository.dart';
import '../../domain/schedule_resolver.dart';

/// Overridden in `main()` with the initialised data source.
final Provider<TimetableLocalDataSource> timetableLocalDataSourceProvider =
    Provider<TimetableLocalDataSource>(
  (ref) => throw UnimplementedError(
    'timetableLocalDataSourceProvider must be overridden in main() with an '
    'initialised TimetableLocalDataSource.',
  ),
);

final Provider<TimetableRepository> timetableRepositoryProvider =
    Provider<TimetableRepository>((ref) {
  return TimetableRepositoryImpl(
    local: ref.watch(timetableLocalDataSourceProvider),
    syncQueue: ref.watch(syncQueueServiceProvider),
    clock: ref.watch(clockProvider),
  );
});

/// Base for state seeded synchronously from Hive and refreshed on box changes.
///
/// This is what lets screens paint real content on their first frame: `build()`
/// reads an already-open box, so there is no loading state to render.
abstract class _WatchingNotifier<T> extends Notifier<T> {
  /// Pulls the current value straight from local storage.
  T readValue(TimetableRepository repository);

  @override
  T build() {
    final TimetableRepository repository =
        ref.watch(timetableRepositoryProvider);

    final StreamSubscription<void> subscription =
        repository.watchChanges().listen((void _) {
      state = readValue(repository);
    });
    ref.onDispose(subscription.cancel);

    return readValue(repository);
  }
}

class PeriodsNotifier extends _WatchingNotifier<List<Period>> {
  @override
  List<Period> readValue(TimetableRepository repository) =>
      repository.periods();
}

final periodsProvider =
    NotifierProvider<PeriodsNotifier, List<Period>>(PeriodsNotifier.new);

class AllEntriesNotifier extends _WatchingNotifier<List<TimetableEntry>> {
  @override
  List<TimetableEntry> readValue(TimetableRepository repository) =>
      repository.allEntries();
}

final allEntriesProvider =
    NotifierProvider<AllEntriesNotifier, List<TimetableEntry>>(
  AllEntriesNotifier.new,
);

/// Entries for one weekday, derived rather than separately watched so the editor
/// tabs share a single subscription.
final entriesForWeekdayProvider =
    Provider.family<List<TimetableEntry>, int>((ref, int weekday) {
  final List<Period> periods = ref.watch(periodsProvider);
  final Map<String, int> order = <String, int>{
    for (final Period p in periods) p.id: p.sortOrder,
  };

  final List<TimetableEntry> entries = ref
      .watch(allEntriesProvider)
      .where((TimetableEntry e) => e.weekday == weekday)
      .toList()
    ..sort(
      (TimetableEntry a, TimetableEntry b) => (order[a.periodId] ?? 1 << 20)
          .compareTo(order[b.periodId] ?? 1 << 20),
    );

  return entries;
});

/// The day the schedule is shown for. Overridable in tests, and the seam a
/// future "look at tomorrow" control would use.
///
/// Self-invalidates just after midnight. Without that, an app left open
/// overnight would keep showing yesterday and — worse — record completions
/// against yesterday's date, since session ids are built from this value.
final selectedDateProvider = Provider<DateTime>((ref) {
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

class ScheduleNotifier extends _WatchingNotifier<List<ScheduledClass>> {
  @override
  List<ScheduledClass> readValue(TimetableRepository repository) =>
      repository.scheduleFor(ref.read(selectedDateProvider));

  @override
  List<ScheduledClass> build() {
    // Rebuild when the target date changes, as well as on data changes.
    ref.watch(selectedDateProvider);
    return super.build();
  }
}

final scheduleProvider =
    NotifierProvider<ScheduleNotifier, List<ScheduledClass>>(
  ScheduleNotifier.new,
);

/// One-second tick, scoped so only the countdown rebuilds on it.
///
/// `autoDispose` matters: the timer stops the moment no widget is watching, so a
/// backgrounded app is not burning battery counting down.
final tickerProvider = StreamProvider.autoDispose<DateTime>((ref) {
  final Clock clock = ref.watch(clockProvider);
  return Stream<DateTime>.periodic(
    const Duration(seconds: 1),
    (int _) => clock.now(),
  );
});

/// Current class, next class and countdowns, recomputed on each tick.
final scheduleSnapshotProvider = Provider.autoDispose<ScheduleSnapshot>((ref) {
  final List<ScheduledClass> schedule = ref.watch(scheduleProvider);
  final DateTime now =
      ref.watch(tickerProvider).valueOrNull ?? ref.watch(clockProvider).now();
  return ScheduleResolver.resolve(schedule, now);
});

/// Lessons that finished without being marked, for an end-of-day nudge.
final unmarkedPastProvider =
    Provider.autoDispose<List<ScheduledClass>>((ref) {
  final List<ScheduledClass> schedule = ref.watch(scheduleProvider);
  final DateTime now =
      ref.watch(tickerProvider).valueOrNull ?? ref.watch(clockProvider).now();
  return ScheduleResolver.unmarkedPast(schedule, now);
});
