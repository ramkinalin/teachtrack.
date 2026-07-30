import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/entities/scheduled_class.dart';
import '../../domain/schedule_resolver.dart';
import '../providers/timetable_providers.dart';

/// The hero card: what is happening now, what is next, and how long is left.
///
/// This is the only widget that watches the one-second ticker, so the rest of
/// the day list never rebuilds on a tick.
class CurrentClassCard extends ConsumerWidget {
  const CurrentClassCard({super.key, this.onMarkComplete});

  final ValueChanged<ScheduledClass>? onMarkComplete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ScheduleSnapshot snapshot = ref.watch(scheduleSnapshotProvider);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    if (snapshot.dayIsOver) {
      return _Shell(
        background: scheme.surfaceContainerHighest,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'No more classes today',
              style: text.titleMedium?.copyWith(color: scheme.onSurface),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Enjoy the rest of your day.',
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    final ScheduledClass? current = snapshot.current;

    if (current == null) {
      final ScheduledClass next = snapshot.next!;
      return _Shell(
        background: scheme.surfaceContainerHighest,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _Label('Free until ${next.period.timeRangeLabel.split(' – ').first}',
                color: scheme.onSurfaceVariant),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _titleFor(next),
              style: text.titleLarge?.copyWith(color: scheme.onSurface),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              _subtitleFor(next),
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (snapshot.untilNextLabel != null) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Starts in ${snapshot.untilNextLabel}',
                style: text.titleSmall?.copyWith(color: scheme.primary),
              ),
            ],
          ],
        ),
      );
    }

    final bool canComplete =
        current.isActionable && !current.isCompleted && onMarkComplete != null;

    return _Shell(
      background: scheme.primaryContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              _Label(
                current.period.isBreak ? 'On break' : 'Now',
                color: scheme.onPrimaryContainer,
              ),
              const Spacer(),
              if (snapshot.remainingLabel != null)
                Text(
                  '${snapshot.remainingLabel} left',
                  style: text.labelLarge
                      ?.copyWith(color: scheme.onPrimaryContainer),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            _titleFor(current),
            style: text.headlineSmall
                ?.copyWith(color: scheme.onPrimaryContainer),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _subtitleFor(current),
            style: text.bodyMedium?.copyWith(color: scheme.onPrimaryContainer),
          ),
          if (snapshot.next != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Divider(color: scheme.onPrimaryContainer.withValues(alpha: 0.2)),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Next · ${_titleFor(snapshot.next!)} · '
              '${snapshot.next!.period.timeRangeLabel}',
              style: text.bodySmall?.copyWith(color: scheme.onPrimaryContainer),
            ),
          ],
          if (canComplete) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: () => onMarkComplete!(current),
              icon: const Icon(Icons.check_rounded),
              label: const Text('Class completed'),
            ),
          ] else if (current.isCompleted) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: <Widget>[
                Icon(
                  Icons.check_circle_rounded,
                  size: 18,
                  color: scheme.onPrimaryContainer,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Marked complete',
                  style: text.labelLarge
                      ?.copyWith(color: scheme.onPrimaryContainer),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _titleFor(ScheduledClass item) => item.period.isBreak
      ? item.period.label
      : '${item.entry.subject} · ${item.entry.classGroup}';

  static String _subtitleFor(ScheduledClass item) {
    final String room = item.entry.room;
    final String time = item.period.timeRangeLabel;
    if (item.period.isBreak) return time;
    return room.isEmpty ? time : '$time · $room';
  }
}

class _Shell extends StatelessWidget {
  const _Shell({required this.child, required this.background});

  final Widget child;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: child,
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text, {required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w700,
          ),
    );
  }
}
