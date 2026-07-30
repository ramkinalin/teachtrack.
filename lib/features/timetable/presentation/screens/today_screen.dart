import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/day_time.dart';
import '../../../../core/utils/result.dart';
import '../../../../core/widgets/sync_status_banner.dart';
import '../../../profile/presentation/profile_providers.dart';
import '../../domain/entities/class_session.dart';
import '../../domain/entities/scheduled_class.dart';
import '../../domain/repositories/timetable_repository.dart';
import '../../domain/schedule_resolver.dart';
import '../providers/timetable_providers.dart';
import '../widgets/current_class_card.dart';
import '../widgets/schedule_entry_tile.dart';
import '../widgets/session_note_sheet.dart';

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

    final String teacherName = ref.watch(
      profileProvider.select(
        (ProfileState profile) => profile.profile?.fullName ?? '',
      ),
    );

    return Scaffold(
      appBar: AppBar(
        // Taller than the 56dp default: the two-line title needs the room once
        // AppBar applies its 1.34x text-scale clamp for accessibility settings.
        toolbarHeight: 72,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(CalendarDay.longLabel(date.weekday)),
            if (teacherName.isNotEmpty)
              Text(
                teacherName,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Edit timetable',
            onPressed: () => context.pushNamed(AppRoutes.timetableName),
            icon: const Icon(Icons.edit_calendar_outlined),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: () => context.pushNamed(AppRoutes.settingsName),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          const SyncStatusBanner(),
          Expanded(
            child: schedule.isEmpty
                ? _EmptyDay(
                    weekday: date.weekday,
                    hasAnyClasses: ref.watch(allEntriesProvider).isNotEmpty,
                  )
                : _DayList(
                    schedule: schedule,
                    currentEntryId: currentEntryId,
                    onAction: (ScheduledClass item, ScheduleRowAction action) =>
                        _handleAction(context, ref, item, action),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleAction(
    BuildContext context,
    WidgetRef ref,
    ScheduledClass item,
    ScheduleRowAction action,
  ) {
    return switch (action) {
      ScheduleRowAction.editNote => _editNote(context, ref, item),
      ScheduleRowAction.markCompleted =>
        _updateStatus(context, ref, item, ClassSessionStatus.completed),
      ScheduleRowAction.markCancelled =>
        _updateStatus(context, ref, item, ClassSessionStatus.cancelled),
      ScheduleRowAction.clear =>
        _updateStatus(context, ref, item, ClassSessionStatus.scheduled),
    };
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
            // A custom Row rather than SnackBar.action because two actions are
            // wanted here and `action` only takes one. Undo has to stay — it is
            // the safety net for a mis-tap on the fast path.
            content: Row(
              children: <Widget>[
                Expanded(
                  child: Text('${item.entry.subject} marked complete'),
                ),
                TextButton(
                  onPressed: () {
                    messenger.hideCurrentSnackBar();
                    unawaited(_editNote(context, ref, item));
                  },
                  child: const Text('Note'),
                ),
                TextButton(
                  onPressed: () {
                    messenger.hideCurrentSnackBar();
                    unawaited(
                      repository.setSessionStatus(
                        entry: item.entry,
                        date: item.date,
                        status: ClassSessionStatus.scheduled,
                      ),
                    );
                  },
                  child: const Text('Undo'),
                ),
              ],
            ),
          ),
        );
      },
      (failure) => messenger.showSnackBar(
        SnackBar(content: Text(failure.message)),
      ),
    );
  }

  Future<void> _editNote(
    BuildContext context,
    WidgetRef ref,
    ScheduledClass item,
  ) async {
    final TimetableRepository repository =
        ref.read(timetableRepositoryProvider);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    final String? note = await SessionNoteSheet.show(
      context,
      title: '${item.entry.subject} · ${item.entry.classGroup} · '
          '${item.period.timeRangeLabel}',
      initialNote: item.session?.note ?? '',
    );

    // null means cancelled; an empty string means the teacher cleared it.
    if (note == null) return;

    final Result<void> result = await repository.setSessionNote(
      entry: item.entry,
      date: item.date,
      note: note,
    );

    result.fold(
      (_) {},
      (failure) =>
          messenger.showSnackBar(SnackBar(content: Text(failure.message))),
    );
  }
}

class _DayList extends StatelessWidget {
  const _DayList({
    required this.schedule,
    required this.onAction,
    this.currentEntryId,
  });

  final List<ScheduledClass> schedule;
  final String? currentEntryId;
  final void Function(ScheduledClass item, ScheduleRowAction action) onAction;

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
                  onAction(item, ScheduleRowAction.markCompleted),
            ),
          );
        }

        if (index == schedule.length + 1) {
          return _UnmarkedNudge(onAction: onAction);
        }

        final ScheduledClass item = schedule[index - 1];
        return ScheduleEntryTile(
          item: item,
          isCurrent: item.entry.id == currentEntryId,
          onAction: (ScheduleRowAction action) => onAction(item, action),
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
  const _UnmarkedNudge({required this.onAction});

  final void Function(ScheduledClass item, ScheduleRowAction action) onAction;

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
                      onAction(item, ScheduleRowAction.markCompleted);
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

/// Empty state that offers the next action rather than just reporting nothing.
class _EmptyDay extends StatelessWidget {
  const _EmptyDay({required this.weekday, required this.hasAnyClasses});

  final int weekday;

  /// Distinguishes "no timetable yet" from "nothing on today" — a teacher with a
  /// full week and a free Saturday should not be told to go set up a timetable.
  final bool hasAnyClasses;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              hasAnyClasses
                  ? Icons.beach_access_outlined
                  : Icons.event_available_outlined,
              size: 40,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              hasAnyClasses
                  ? 'No classes on ${CalendarDay.longLabel(weekday)}'
                  : 'Your timetable is empty',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              hasAnyClasses
                  ? 'Enjoy the day off.'
                  : 'Add your classes once and TeachTrack shows them every week.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            if (!hasAnyClasses) ...<Widget>[
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: () => context.pushNamed(AppRoutes.timetableName),
                icon: const Icon(Icons.add),
                label: const Text('Add your timetable'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
