import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/day_time.dart';
import '../../domain/entities/scheduled_class.dart';

/// What a teacher can do to one row of the day list.
enum ScheduleRowAction { markCompleted, markCancelled, clear, editNote }

/// One row in the day list.
///
/// Marking complete is a single tap on the trailing control — the workflow a
/// teacher runs twenty times a day should never take two. Everything else lives
/// behind the overflow menu.
class ScheduleEntryTile extends StatelessWidget {
  const ScheduleEntryTile({
    required this.item,
    super.key,
    this.onAction,
    this.isCurrent = false,
  });

  final ScheduledClass item;
  final ValueChanged<ScheduleRowAction>? onAction;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    if (item.period.isBreak) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 56,
              child: Text(
                DayTime.format(item.period.startMinute),
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            Expanded(
              child: Text(
                item.period.label,
                style: text.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final bool completed = item.isCompleted;
    final bool cancelled = item.isCancelled;
    final String note = item.session?.note ?? '';

    return Card(
      color: isCurrent ? scheme.secondaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            SizedBox(
              width: 56,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    DayTime.format(item.period.startMinute),
                    style: text.titleSmall,
                  ),
                  Text(
                    DayTime.format(item.period.endMinute),
                    style: text.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          item.entry.subject,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleMedium?.copyWith(
                            decoration:
                                cancelled ? TextDecoration.lineThrough : null,
                          ),
                        ),
                      ),
                      if (item.entry.isPhysicalEducation) ...<Widget>[
                        const SizedBox(width: AppSpacing.sm),
                        Icon(
                          Icons.sports_soccer_rounded,
                          size: 16,
                          color: scheme.onSurfaceVariant,
                        ),
                      ],
                      // On duty is the obligation you get in trouble for missing,
                      // so it earns a marker of its own.
                      if (item.isInvigilating) ...<Widget>[
                        const SizedBox(width: AppSpacing.sm),
                        Icon(
                          Icons.how_to_reg_outlined,
                          size: 16,
                          color: scheme.primary,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _subtitle(),
                    style: text.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  if (note.isNotEmpty) ...<Widget>[
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Icon(
                          Icons.sticky_note_2_outlined,
                          size: 14,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            note,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall?.copyWith(
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (onAction != null)
              _ActionControls(
                completed: completed,
                cancelled: cancelled,
                hasNote: note.isNotEmpty,
                onAction: onAction!,
              ),
          ],
        ),
      ),
    );
  }

  String _subtitle() {
    final String slotSubject = item.slot?.subject ?? '';

    final List<String> parts = <String>[
      if (item.entry.classGroup.isNotEmpty) item.entry.classGroup,
      if (slotSubject.isNotEmpty) slotSubject,
      if (item.entry.room.isNotEmpty) item.entry.room,
      if (item.isInvigilating) 'On duty',
      if (item.isMySubject && !item.isInvigilating) 'Your subject',
      if (item.isCancelled) 'Cancelled',
    ];
    return parts.join(' · ');
  }
}

class _ActionControls extends StatelessWidget {
  const _ActionControls({
    required this.completed,
    required this.cancelled,
    required this.hasNote,
    required this.onAction,
  });

  final bool completed;
  final bool cancelled;
  final bool hasNote;
  final ValueChanged<ScheduleRowAction> onAction;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Row(
      children: <Widget>[
        IconButton(
          tooltip: completed ? 'Undo completion' : 'Mark class completed',
          onPressed: () => onAction(
            completed ? ScheduleRowAction.clear : ScheduleRowAction.markCompleted,
          ),
          icon: Icon(
            completed
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            color: completed ? scheme.primary : scheme.onSurfaceVariant,
          ),
        ),
        PopupMenuButton<ScheduleRowAction>(
          tooltip: 'More',
          onSelected: onAction,
          itemBuilder: (BuildContext context) =>
              <PopupMenuEntry<ScheduleRowAction>>[
            PopupMenuItem<ScheduleRowAction>(
              value: ScheduleRowAction.editNote,
              child: Text(hasNote ? 'Edit note' : 'Add note'),
            ),
            if (!completed)
              const PopupMenuItem<ScheduleRowAction>(
                value: ScheduleRowAction.markCompleted,
                child: Text('Mark completed'),
              ),
            if (!cancelled)
              const PopupMenuItem<ScheduleRowAction>(
                value: ScheduleRowAction.markCancelled,
                child: Text('Mark cancelled'),
              ),
            if (completed || cancelled)
              const PopupMenuItem<ScheduleRowAction>(
                value: ScheduleRowAction.clear,
                child: Text('Clear status'),
              ),
          ],
        ),
      ],
    );
  }
}
