import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/day_time.dart';
import '../../../../shared/providers/today_provider.dart';
import '../../domain/entities/school_event.dart';
import '../providers/event_providers.dart';
import 'event_tile.dart';

/// Compact "coming up this week" card for the home screen.
///
/// Shows at most three, because the point is a glance rather than a list — the
/// full picture is one tap away on the events screen.
class UpcomingEventsBanner extends ConsumerWidget {
  const UpcomingEventsBanner({super.key});

  static const int _maxShown = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<SchoolEvent> events = ref.watch(imminentEventsProvider);
    if (events.isEmpty) return const SizedBox.shrink();

    final DateTime today = ref.watch(todayProvider);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final List<SchoolEvent> shown = events.take(_maxShown).toList();

    return Card(
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.upcoming_outlined, size: 18, color: scheme.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Coming up',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                TextButton(
                  onPressed: () => context.pushNamed(AppRoutes.eventsName),
                  child: Text(
                    events.length > _maxShown
                        ? 'All ${events.length}'
                        : 'View all',
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            for (final SchoolEvent event in shown)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Row(
                  children: <Widget>[
                    Icon(
                      iconForCategory(event.category),
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        event.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      _whenLabel(event, today),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _whenLabel(SchoolEvent event, DateTime today) {
    // Differenced in UTC: two local midnights are 23 or 25 hours apart across a
    // daylight-saving change, which would make tomorrow read as today.
    final int days = DateTime.utc(
      event.date.year,
      event.date.month,
      event.date.day,
    ).difference(DateTime.utc(today.year, today.month, today.day)).inDays;

    return switch (days) {
      < 0 => CalendarDay.key(event.date),
      0 => event.isAllDay ? 'Today' : 'Today ${event.timeLabel}',
      1 => 'Tomorrow',
      _ => 'In $days days',
    };
  }
}
