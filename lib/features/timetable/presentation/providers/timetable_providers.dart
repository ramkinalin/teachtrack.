import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/clock.dart';
import '../../../../core/utils/day_time.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../../../shared/providers/today_provider.dart';
import '../../data/local/override_local_data_source.dart';
import '../../data/local/subject_store.dart';
import '../../data/local/timetable_local_data_source.dart';
import '../../data/repositories/override_repository_impl.dart';
import '../../data/repositories/timetable_repository_impl.dart';
import '../../domain/entities/period.dart';
import '../../domain/entities/schedule_override.dart';
import '../../domain/entities/scheduled_class.dart';
import '../../domain/entities/timetable_entry.dart';
import '../../domain/repositories/override_repository.dart';
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

final subjectStoreProvider = Provider<SubjectStore>((ref) {
  return SubjectStore(
    settingsBox: ref.watch(localStorageServiceProvider).settingsBox,
  );
});

/// Overridden in `main()` with the initialised data source.
final overrideLocalDataSourceProvider = Provider<OverrideLocalDataSource>(
  (ref) => throw UnimplementedError(
    'overrideLocalDataSourceProvider must be overridden in main() with an '
    'initialised OverrideLocalDataSource.',
  ),
);

final overrideRepositoryProvider = Provider<OverrideRepository>((ref) {
  return OverrideRepositoryImpl(
    local: ref.watch(overrideLocalDataSourceProvider),
    syncQueue: ref.watch(syncQueueServiceProvider),
    clock: ref.watch(clockProvider),
  );
});

final Provider<TimetableRepository> timetableRepositoryProvider =
    Provider<TimetableRepository>((ref) {
  return TimetableRepositoryImpl(
    local: ref.watch(timetableLocalDataSourceProvider),
    subjects: ref.watch(subjectStoreProvider),
    syncQueue: ref.watch(syncQueueServiceProvider),
    overrides: ref.watch(overrideLocalDataSourceProvider),
    clock: ref.watch(clockProvider),
  );
});

/// Every override, for the list screen. Refreshes when any is saved or deleted.
final overridesListProvider = Provider<List<ScheduleOverride>>((ref) {
  final OverrideRepository repository = ref.watch(overrideRepositoryProvider);

  final StreamSubscription<void> subscription =
      repository.watchChanges().listen((void _) => ref.invalidateSelf());
  ref.onDispose(subscription.cancel);

  return repository.all();
});

/// The override covering the shown day, or `null` on a normal day.
///
/// Self-invalidates when overrides change, so the value itself is the signal —
/// an earlier version returned a counter that never actually changed, so nothing
/// downstream ever rebuilt.
final activeOverrideProvider = Provider<ScheduleOverride?>((ref) {
  final OverrideRepository repository = ref.watch(overrideRepositoryProvider);

  final StreamSubscription<void> subscription =
      repository.watchChanges().listen((void _) => ref.invalidateSelf());
  ref.onDispose(subscription.cancel);

  return repository.covering(ref.watch(selectedDateProvider));
});

/// Subject names for the entry form dropdown, refreshed when the list is edited.
final subjectsProvider = Provider<List<String>>((ref) {
  final TimetableRepository repository =
      ref.watch(timetableRepositoryProvider);

  // Kept as a plain Provider seeded synchronously, then invalidated on change,
  // so the dropdown has real options on its very first build.
  final StreamSubscription<void> subscription =
      repository.watchSubjects().listen((void _) => ref.invalidateSelf());
  ref.onDispose(subscription.cancel);

  return repository.subjects();
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

/// The day the schedule is shown for, and the seam a future "look at tomorrow"
/// control would override.
///
/// Delegates to [todayProvider], which handles the midnight rollover — without
/// it an app left open overnight would record completions against yesterday,
/// since session ids are built from this value.
final selectedDateProvider =
    Provider<DateTime>((ref) => ref.watch(todayProvider));

class ScheduleNotifier extends _WatchingNotifier<List<ScheduledClass>> {
  @override
  List<ScheduledClass> readValue(TimetableRepository repository) =>
      repository.scheduleFor(ref.read(selectedDateProvider));

  @override
  List<ScheduledClass> build() {
    // Rebuild when the target date changes, as well as on data changes — and
    // when an override appears or goes, since that replaces the whole day.
    ref.watch(selectedDateProvider);
    ref.watch(activeOverrideProvider);
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

/// Minute-of-day, derived from the ticker.
///
/// Anything that only changes when the clock crosses a minute should watch this
/// rather than the raw tick — an `int` compares by value, so watchers are left
/// alone for 59 of every 60 seconds.
final currentMinuteProvider = Provider.autoDispose<int>((ref) {
  final DateTime now =
      ref.watch(tickerProvider).valueOrNull ?? ref.watch(clockProvider).now();
  return DayTime.fromDateTime(now);
});

/// Lessons that finished without being marked, for an end-of-day nudge.
///
/// Deliberately driven by [currentMinuteProvider], not the ticker: whether a
/// lesson has finished can only change on a minute boundary, and this returns a
/// fresh list each time it runs, which a `Provider` cannot deduplicate.
final unmarkedPastProvider =
    Provider.autoDispose<List<ScheduledClass>>((ref) {
  return ScheduleResolver.unmarkedPast(
    ref.watch(scheduleProvider),
    ref.watch(currentMinuteProvider),
  );
});
