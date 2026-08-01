import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/result.dart';
import '../../../../core/widgets/app_state_views.dart';
import '../../../../shared/providers/today_provider.dart';
import '../../domain/entities/schedule_schedule.dart';
import '../../domain/repositories/override_repository.dart';
import '../providers/timetable_providers.dart';
import 'override_editor_screen.dart';

/// Exam weeks, holidays and special days.
class OverridesScreen extends ConsumerWidget {
  const OverridesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<ScheduleOverride> overrides = ref.watch(overridesListProvider);
    final DateTime today = ref.watch(todayProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Exams and holidays')),
      body: overrides.isEmpty
          ? const AppEmptyView(
              icon: Icons.event_note_outlined,
              title: 'No special schedules',
              subtitle: 'Add an exam week, a holiday or a special day and your '
                  'normal timetable steps aside on those dates.',
            )
          : ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: overrides.length,
              separatorBuilder: (BuildContext context, int index) =>
                  const SizedBox(height: AppSpacing.sm),
              itemBuilder: (BuildContext context, int index) {
                final ScheduleOverride item = overrides[index];
                return _OverrideCard(
                  schedule: item,
                  today: today,
                  onTap: () => _open(context, existing: item),
                  onDelete: () => _delete(context, ref, item),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(context),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
    );
  }

  Future<void> _open(BuildContext context, {ScheduleOverride? existing}) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            OverrideEditorScreen(existing: existing),
      ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    ScheduleOverride item,
  ) async {
    final OverrideRepository repository = ref.read(overrideRepositoryProvider);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    final Result<void> result = await repository.delete(item.id);

    result.fold(
      (_) => messenger.showSnackBar(
        SnackBar(
          content: Text('Deleted ${item.name}'),
          // Undo rather than a confirmation: an exam week takes a while to enter,
          // so losing one to a mis-tap needs a way back, but a modal every time
          // would be tiresome.
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => repository.upsert(item),
          ),
        ),
      ),
      (failure) =>
          messenger.showSnackBar(SnackBar(content: Text(failure.message))),
    );
  }
}

class _OverrideCard extends StatelessWidget {
  const _OverrideCard({
    required this.schedule,
    required this.today,
    required this.onTap,
    required this.onDelete,
  });

  /// Deliberately not named `override`: `dart:core` declares `const Object
  /// override`, so a member of that name shadows the `@override` annotation for
  /// the whole class and produces errors that point nowhere near the cause.
  final ScheduleOverride schedule;
  final DateTime today;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool isActive = schedule.covers(today);
    final bool hasFinished = schedule.endDate.isBefore(today);

    return Card(
      color: isActive ? scheme.tertiaryContainer : null,
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          schedule.isHoliday
              ? Icons.beach_access_outlined
              : Icons.event_note_outlined,
          color: hasFinished ? scheme.onSurfaceVariant : scheme.primary,
        ),
        title: Text(schedule.name),
        isThreeLine: true,
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('${schedule.kind.label} · ${schedule.rangeLabel}'),
            Text(
              _statusLine(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
        trailing: IconButton(
          tooltip: 'Delete',
          icon: const Icon(Icons.delete_outline_rounded),
          onPressed: onDelete,
        ),
      ),
    );
  }

  String _statusLine() {
    if (schedule.covers(today)) return 'Happening now';
    if (schedule.endDate.isBefore(today)) return 'Finished';

    final int days = DateTime.utc(
      schedule.startDate.year,
      schedule.startDate.month,
      schedule.startDate.day,
    ).difference(DateTime.utc(today.year, today.month, today.day)).inDays;

    final String when = switch (days) {
      1 => 'Starts tomorrow',
      _ => 'Starts in $days days',
    };

    if (schedule.isHoliday) return when;

    final int sittings = schedule.slots.length;
    return sittings == 0
        ? '$when · no sittings added yet'
        : '$when · $sittings sitting${sittings == 1 ? '' : 's'}';
  }
}
