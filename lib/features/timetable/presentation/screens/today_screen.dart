import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/day_time.dart';
import '../../../../core/utils/result.dart';
import '../../../../core/widgets/app_state_views.dart';
import '../../../../core/widgets/sync_status_banner.dart';
import '../../domain/entities/class_session.dart';
import '../../domain/entities/scheduled_class.dart';
import '../../domain/repositories/timetable_repository.dart';
import '../../domain/schedule_resolver.dart';
import '../providers/timetable_providers.dart';
import '../widgets/current_class_card.dart';
import '../widgets/schedule_entry_tile.dart';

/// Today's schedule — the app's home screen.
///
/// Renders from local storage on the first frame, so it is identical online and
/// offline. Status changes write locally and return immediately.
class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<ScheduledClass> schedule = ref.watch(scheduleProvider);
    final DateTime date = ref.watch(selectedDateProvider);

    // Only the id is watched, not the whole snapshot: watching the snapshot here
    // would rebuild the entire list once per second, since the countdown changes
    // on every tick. The countdown itself lives inside CurrentClassCard.
    final String? currentEntryId = ref.watch(
      scheduleSnapshotProvider.select(
        (ScheduleSnapshot snapshot) => snapshot.current?.entry.id,
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(CalendarDay.longLabel(date.weekday)),
        actions: <Widget>[
          IconButton(
            tooltip: 'Edit timetable',
            onPressed: () => context.pushNamed(AppRoutes.timetableName),
            icon: const Icon(Icons.edit_calendar_outlined),
          ),
          if (kDebugMode)
            IconButton(
              tooltip: 'Sync diagnostics',
              onPressed: () => context.pushNamed(AppRoutes.diagnosticsName),
              icon: const Icon(Icons.bug_report_outlined),
            ),
        ],
      ),
      body: Column(
        children: <Widget>[
          const SyncStatusBanner(),
          Expanded(
            child: schedule.isEmpty
                ? _EmptyDay(weekday: date.weekday)
                : _DayList(
                    schedule: schedule,
                    currentEntryId: currentEntryId,
                    onStatusChanged: (ScheduledClass item,
                            ClassSessionStatus status) =>
                        _updateStatus(context, ref, item, status),
                  ),
          ),
        ],
      ),
    );
  }

  /// Writes locally and reports only genuine failures. The absence of a network
  /// is never surfaced as an error here — that is the outbox's business.
  Future<void> _updateStatus(
    BuildContext context,
    WidgetRef ref,
    ScheduledClass item,
    ClassSessionStatus status,
  ) async {
    final TimetableRepository repository =
        ref.read(timetableRepositoryProvider);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    final Result<void> result = await repository.setSessionStatus(
      entry: item.entry,
      date: item.date,
      status: status,
    );

    result.fold(
      (_) {
        if (status != ClassSessionStatus.completed) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text('${item.entry.subject} marked complete'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => repository.setSessionStatus(
                entry: item.entry,
                date: item.date,
                status: ClassSessionStatus.scheduled,
              ),
            ),
          ),
        );
      },
      (failure) => messenger.showSnackBar(
        SnackBar(content: Text(failure.message)),
      ),
    );
  }
}

class _DayList extends StatelessWidget {
  const _DayList({
    required this.schedule,
    required this.onStatusChanged,
    this.currentEntryId,
  });

  final List<ScheduledClass> schedule;
  final String? currentEntryId;
  final void Function(ScheduledClass item, ClassSessionStatus status)
      onStatusChanged;

  @override
  Widget build(BuildContext context) {
    // Index 0 is the hero card, the last index is the unmarked-classes nudge.
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: schedule.length + 2,
      separatorBuilder: (BuildContext context, int index) =>
          const SizedBox(height: AppSpacing.sm),
      itemBuilder: (BuildContext context, int index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: CurrentClassCard(
              onMarkComplete: (ScheduledClass item) =>
                  onStatusChanged(item, ClassSessionStatus.completed),
            ),
          );
        }

        if (index == schedule.length + 1) {
          return _UnmarkedNudge(onStatusChanged: onStatusChanged);
        }

        final ScheduledClass item = schedule[index - 1];
        return ScheduleEntryTile(
          item: item,
          isCurrent: item.entry.id == currentEntryId,
          onStatusChanged: (ClassSessionStatus status) =>
              onStatusChanged(item, status),
        );
      },
    );
  }
}

/// Gentle reminder about lessons that finished without being marked.
///
/// Deliberately not a modal or a notification: a teacher who chose not to mark a
/// class should not have to dismiss anything.
class _UnmarkedNudge extends ConsumerWidget {
  const _UnmarkedNudge({required this.onStatusChanged});

  final void Function(ScheduledClass item, ClassSessionStatus status)
      onStatusChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<ScheduledClass> unmarked = ref.watch(unmarkedPastProvider);
    if (unmarked.isEmpty) return const SizedBox.shrink();

    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Card(
        color: scheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '${unmarked.length} finished '
                '${unmarked.length == 1 ? 'class' : 'classes'} not marked',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonal(
                  onPressed: () {
                    for (final ScheduledClass item in unmarked) {
                      onStatusChanged(item, ClassSessionStatus.completed);
                    }
                  },
                  child: const Text('Mark all completed'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyDay extends StatelessWidget {
  const _EmptyDay({required this.weekday});

  final int weekday;

  @override
  Widget build(BuildContext context) {
    return AppEmptyView(
      icon: Icons.event_available_outlined,
      title: 'Nothing scheduled for ${CalendarDay.longLabel(weekday)}',
      subtitle: 'Add classes from the timetable editor to see them here.',
    );
  }
}
