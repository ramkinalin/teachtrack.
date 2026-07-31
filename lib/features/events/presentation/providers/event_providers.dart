import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/day_time.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../../../shared/providers/today_provider.dart';
import '../../data/local/event_local_data_source.dart';
import '../../data/repositories/event_repository_impl.dart';
import '../../domain/entities/school_event.dart';
import '../../domain/repositories/event_repository.dart';

/// Overridden in `main()` with the initialised data source.
final eventLocalDataSourceProvider = Provider<EventLocalDataSource>(
  (ref) => throw UnimplementedError(
    'eventLocalDataSourceProvider must be overridden in main() with an '
    'initialised EventLocalDataSource.',
  ),
);

final eventRepositoryProvider = Provider<EventRepository>((ref) {
  return EventRepositoryImpl(
    local: ref.watch(eventLocalDataSourceProvider),
    syncQueue: ref.watch(syncQueueServiceProvider),
    clock: ref.watch(clockProvider),
  );
});

/// Upcoming events, seeded synchronously from Hive and refreshed on change.
///
/// Watches [todayProvider] so the window moves at midnight rather than staying
/// frozen at whenever the app happened to be opened.
class UpcomingEventsNotifier extends Notifier<List<SchoolEvent>> {
  @override
  List<SchoolEvent> build() {
    final EventRepository repository = ref.watch(eventRepositoryProvider);
    final DateTime today = ref.watch(todayProvider);

    final StreamSubscription<void> subscription = repository
        .watchChanges()
        .listen((void _) => state = repository.upcoming(from: today));
    ref.onDispose(subscription.cancel);

    return repository.upcoming(from: today);
  }
}

final upcomingEventsProvider =
    NotifierProvider<UpcomingEventsNotifier, List<SchoolEvent>>(
  UpcomingEventsNotifier.new,
);

/// Events in the next week, for the home-screen banner.
///
/// Derived from [upcomingEventsProvider] rather than querying again, so there is
/// one subscription and one source of truth.
final imminentEventsProvider = Provider<List<SchoolEvent>>((ref) {
  final DateTime today = ref.watch(todayProvider);
  final DateTime horizon = DateTime(today.year, today.month, today.day + 7);

  return ref
      .watch(upcomingEventsProvider)
      .where((SchoolEvent e) => e.date.isBefore(horizon))
      .toList(growable: false);
});

/// Events on one specific date, for a day view.
///
/// `autoDispose` and keyed on a date string rather than a `DateTime`: a
/// microsecond-precise key would miss the cache on every call and leave a
/// provider entry behind for the life of the app.
final eventsForDayProvider =
    Provider.autoDispose.family<List<SchoolEvent>, String>((ref, String dayKey) {
  // Watched so the list refreshes when anything changes.
  ref.watch(upcomingEventsProvider);
  final DateTime? date = DateTime.tryParse(dayKey);
  if (date == null) return const <SchoolEvent>[];
  return ref.watch(eventRepositoryProvider).forDate(date);
});

/// Key helper so callers cannot accidentally pass a timestamped date.
String eventsDayKey(DateTime date) => CalendarDay.key(date);
