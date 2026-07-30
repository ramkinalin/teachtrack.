import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/day_time.dart';
import '../../domain/entities/class_session.dart';
import '../../domain/entities/scheduled_class.dart';

/// One row in the day list.
///
/// Marking complete is a single tap on the trailing control — the workflow a
/// teacher runs twenty times a day should never take two.
class ScheduleEntryTile extends StatelessWidget {
  const ScheduleEntryTile({
    required this.item,
    super.key,
    this.onStatusChanged,
    this.isCurrent = false,
  });

  final ScheduledClass item;
  final ValueChanged<ClassSessionStatus>? onStatusChanged;
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
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _subtitle(),
                    style: text.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (onStatusChanged != null)
              _StatusControl(
                completed: completed,
                cancelled: cancelled,
                onStatusChanged: onStatusChanged!,
              ),
          ],
        ),
      ),
    );
  }

  String _subtitle() {
    final List<String> parts = <String>[
      item.entry.classGroup,
      if (item.entry.room.isNotEmpty) item.entry.room,
      if (item.isCancelled) 'Cancelled',
    ];
    return parts.join(' · ');
  }
}

class _StatusControl extends StatelessWidget {
  const _StatusControl({
    required this.completed,
    required this.cancelled,
    required this.onStatusChanged,
  });

  final bool completed;
  final bool cancelled;
  final ValueChanged<ClassSessionStatus> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Row(
      children: <Widget>[
        IconButton(
          tooltip: completed ? 'Undo completion' : 'Mark class completed',
          onPressed: () => onStatusChanged(
            completed
                ? ClassSessionStatus.scheduled
                : ClassSessionStatus.completed,
          ),
          icon: Icon(
            completed
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            color: completed ? scheme.primary : scheme.onSurfaceVariant,
          ),
        ),
        PopupMenuButton<ClassSessionStatus>(
          tooltip: 'More',
          onSelected: onStatusChanged,
          itemBuilder: (BuildContext context) =>
              <PopupMenuEntry<ClassSessionStatus>>[
            if (!completed)
              const PopupMenuItem<ClassSessionStatus>(
                value: ClassSessionStatus.completed,
                child: Text('Mark completed'),
              ),
            if (!cancelled)
              const PopupMenuItem<ClassSessionStatus>(
                value: ClassSessionStatus.cancelled,
                child: Text('Mark cancelled'),
              ),
            if (completed || cancelled)
              const PopupMenuItem<ClassSessionStatus>(
                value: ClassSessionStatus.scheduled,
                child: Text('Clear'),
              ),
          ],
        ),
      ],
    );
  }
}
