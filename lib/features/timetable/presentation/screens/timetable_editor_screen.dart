import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/day_time.dart';
import '../../../../core/utils/result.dart';
import '../../../../core/widgets/app_state_views.dart';
import '../../domain/entities/period.dart';
import '../../domain/entities/timetable_entry.dart';
import '../../domain/repositories/timetable_repository.dart';
import '../providers/timetable_providers.dart';
import '../widgets/entry_form_sheet.dart';

/// Weekly timetable editor: one tab per teaching day.
///
/// The tab layout doubles as the week view — every entry for a day is visible in
/// period order, so no separate weekly grid is needed.
class TimetableEditorScreen extends ConsumerStatefulWidget {
  const TimetableEditorScreen({super.key});

  @override
  ConsumerState<TimetableEditorScreen> createState() =>
      _TimetableEditorScreenState();
}

class _TimetableEditorScreenState extends ConsumerState<TimetableEditorScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  static const List<int> _days = CalendarDay.teachingWeek;

  @override
  void initState() {
    super.initState();
    final int todayIndex = _days.indexOf(DateTime.now().weekday);
    _tabController = TabController(
      length: _days.length,
      initialIndex: todayIndex == -1 ? 0 : todayIndex,
      vsync: this,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<Period> periods = ref.watch(periodsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Timetable'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: <Widget>[
            for (final int weekday in _days)
              Tab(text: CalendarDay.shortLabel(weekday)),
          ],
        ),
      ),
      body: periods.isEmpty
          ? const AppEmptyView(
              icon: Icons.schedule_outlined,
              title: 'No bell schedule yet',
              subtitle: 'Periods must exist before classes can be added.',
            )
          : TabBarView(
              controller: _tabController,
              children: <Widget>[
                for (final int weekday in _days)
                  _DayEditor(weekday: weekday, periods: periods),
              ],
            ),
      floatingActionButton: periods.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openForm(_days[_tabController.index]),
              icon: const Icon(Icons.add),
              label: const Text('Add class'),
            ),
    );
  }

  Future<void> _openForm(int weekday, {TimetableEntry? existing}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext context) =>
          EntryFormSheet(weekday: weekday, existing: existing),
    );
  }
}

class _DayEditor extends ConsumerWidget {
  const _DayEditor({required this.weekday, required this.periods});

  final int weekday;
  final List<Period> periods;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<TimetableEntry> entries =
        ref.watch(entriesForWeekdayProvider(weekday));

    if (entries.isEmpty) {
      return AppEmptyView(
        icon: Icons.event_note_outlined,
        title: 'No classes on ${CalendarDay.longLabel(weekday)}',
        subtitle: 'Tap “Add class” to build this day.',
      );
    }

    final Map<String, Period> periodById = <String, Period>{
      for (final Period p in periods) p.id: p,
    };

    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: entries.length,
      separatorBuilder: (BuildContext context, int index) =>
          const SizedBox(height: AppSpacing.sm),
      itemBuilder: (BuildContext context, int index) {
        final TimetableEntry entry = entries[index];
        final Period? period = periodById[entry.periodId];

        return Card(
          child: ListTile(
            title: Text('${entry.subject} · ${entry.classGroup}'),
            subtitle: Text(_subtitle(entry, period)),
            leading: Icon(
              entry.isPhysicalEducation
                  ? Icons.sports_soccer_rounded
                  : Icons.menu_book_rounded,
            ),
            trailing: IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () => _confirmDelete(context, ref, entry),
            ),
            onTap: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              builder: (BuildContext context) =>
                  EntryFormSheet(weekday: weekday, existing: entry),
            ),
          ),
        );
      },
    );
  }

  static String _subtitle(TimetableEntry entry, Period? period) {
    final List<String> parts = <String>[
      if (period == null) 'Period missing' else period.label,
      if (period != null) period.timeRangeLabel,
      if (entry.room.isNotEmpty) entry.room,
    ];
    return parts.join(' · ');
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    TimetableEntry entry,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Delete class?'),
        content: Text(
          '${entry.subject} · ${entry.classGroup} will be removed from '
          '${CalendarDay.longLabel(entry.weekday)}.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final TimetableRepository repository =
        ref.read(timetableRepositoryProvider);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final Result<void> result = await repository.deleteEntry(entry.id);

    result.fold(
      (_) => messenger.showSnackBar(
        const SnackBar(content: Text('Class deleted')),
      ),
      (failure) => messenger.showSnackBar(
        SnackBar(content: Text(failure.message)),
      ),
    );
  }
}
