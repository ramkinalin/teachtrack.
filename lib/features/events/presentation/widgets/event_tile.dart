import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/day_time.dart';
import '../../domain/entities/school_event.dart';

/// Icon for each category, so a fixture is distinguishable from a test at a
/// glance without reading.
IconData iconForCategory(SchoolEventCategory category) => switch (category) {
      SchoolEventCategory.classTest => Icons.assignment_outlined,
      SchoolEventCategory.match => Icons.sports_cricket_outlined,
      SchoolEventCategory.tournament => Icons.emoji_events_outlined,
      SchoolEventCategory.examDuty => Icons.how_to_reg_outlined,
      SchoolEventCategory.meeting => Icons.groups_outlined,
      SchoolEventCategory.other => Icons.event_outlined,
    };

class EventTile extends StatelessWidget {
  const EventTile({
    required this.event,
    required this.today,
    super.key,
    this.onTap,
    this.onDelete,
  });

  final SchoolEvent event;

  /// Used to phrase the date relative to now — "Today" reads better than a date.
  final DateTime today;

  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final String subtitle = event.subtitle;

    return Card(
      child: ListTile(
        onTap: onTap,
        leading: Icon(iconForCategory(event.category), color: scheme.primary),
        title: Text(event.title),
        isThreeLine: subtitle.isNotEmpty,
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('${_relativeDate()} · ${event.timeLabel}'),
            if (subtitle.isNotEmpty)
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (event.hasReminders)
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.xs),
                child: Icon(
                  Icons.notifications_active_outlined,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            if (onDelete != null)
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: onDelete,
              ),
          ],
        ),
      ),
    );
  }

  /// "Today", "Tomorrow", "In 3 days", then a plain date beyond a week.
  String _relativeDate() {
    final DateTime day = CalendarDay.dateOnly(event.date);
    // Differenced in UTC: two local midnights are 23 or 25 hours apart across a
    // daylight-saving change, which would make tomorrow read as today.
    final int days = DateTime.utc(day.year, day.month, day.day)
        .difference(DateTime.utc(today.year, today.month, today.day))
        .inDays;

    return switch (days) {
      < 0 => '${CalendarDay.shortLabel(day.weekday)} ${CalendarDay.key(day)}',
      0 => 'Today',
      1 => 'Tomorrow',
      < 7 => '${CalendarDay.longLabel(day.weekday)}, in $days days',
      _ => '${CalendarDay.shortLabel(day.weekday)} ${CalendarDay.key(day)}',
    };
  }
}
