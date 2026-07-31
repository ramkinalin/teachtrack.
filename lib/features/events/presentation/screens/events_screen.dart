import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/result.dart';
import '../../../../core/widgets/app_state_views.dart';
import '../../../../shared/providers/today_provider.dart';
import '../../domain/entities/school_event.dart';
import '../../domain/repositories/event_repository.dart';
import '../providers/event_providers.dart';
import '../widgets/event_form_sheet.dart';
import '../widgets/event_tile.dart';

/// Tests, matches, tournaments and duties, soonest first.
class EventsScreen extends ConsumerWidget {
  const EventsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<SchoolEvent> events = ref.watch(upcomingEventsProvider);
    final DateTime today = ref.watch(todayProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Events')),
      body: events.isEmpty
          ? const AppEmptyView(
              icon: Icons.event_outlined,
              title: 'Nothing coming up',
              subtitle: 'Add a class test, a match, a tournament or an exam '
                  'duty and it will remind you.',
            )
          : ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: events.length,
              separatorBuilder: (BuildContext context, int index) =>
                  const SizedBox(height: AppSpacing.sm),
              itemBuilder: (BuildContext context, int index) {
                final SchoolEvent event = events[index];
                return EventTile(
                  event: event,
                  today: today,
                  onTap: () => EventFormSheet.show(context, existing: event),
                  onDelete: () => _delete(context, ref, event),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => EventFormSheet.show(context),
        icon: const Icon(Icons.add),
        label: const Text('Add event'),
      ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    SchoolEvent event,
  ) async {
    final EventRepository repository = ref.read(eventRepositoryProvider);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    final Result<void> result = await repository.delete(event.id);

    result.fold(
      (_) => messenger.showSnackBar(
        SnackBar(
          content: Text('Deleted ${event.title}'),
          // Undo rather than a confirmation dialog: one tap to reverse beats two
          // taps to proceed, and nothing here is destructive enough to warrant a
          // modal.
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => repository.upsert(event),
          ),
        ),
      ),
      (failure) =>
          messenger.showSnackBar(SnackBar(content: Text(failure.message))),
    );
  }
}
