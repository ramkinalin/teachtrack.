import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/result.dart';
import '../../../timetable/domain/repositories/timetable_repository.dart';
import '../../../timetable/presentation/providers/timetable_providers.dart';

/// Edit the subject list offered by the entry form.
///
/// Removing a subject here never touches existing classes: an entry stores its
/// subject as text, so the list only controls what the dropdown offers.
class ManageSubjectsScreen extends ConsumerWidget {
  const ManageSubjectsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<String> subjects = ref.watch(subjectsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Subjects'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Restore the default list',
            icon: const Icon(Icons.restore_rounded),
            onPressed: () => _restoreDefaults(context, ref),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Text(
              'These appear in the Subject dropdown when you add a class. '
              'Removing one here does not change classes you have already added.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemCount: subjects.length,
              itemBuilder: (BuildContext context, int index) {
                final String subject = subjects[index];
                return ListTile(
                  title: Text(subject),
                  trailing: IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => _remove(context, ref, subject),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add subject'),
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final TextEditingController controller = TextEditingController();

    try {
      final String? entered = await showDialog<String>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('Add subject'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Subject name'),
            onSubmitted: (String value) =>
                Navigator.of(context).pop(value.trim()),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Add'),
            ),
          ],
        ),
      );

      if (entered == null || entered.isEmpty || !context.mounted) return;

      final TimetableRepository repository =
          ref.read(timetableRepositoryProvider);
      final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

      // Checked before the write: adding a duplicate is a no-op, and silence
      // would look like the button did nothing.
      final bool alreadyPresent = ref.read(subjectsProvider).any(
            (String s) => s.toLowerCase() == entered.toLowerCase(),
          );

      final Result<String> result = await repository.addSubject(entered);

      result.fold(
        (String canonical) {
          if (alreadyPresent) {
            messenger.showSnackBar(
              SnackBar(content: Text('"$canonical" is already in the list')),
            );
          }
        },
        (failure) =>
            messenger.showSnackBar(SnackBar(content: Text(failure.message))),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    String subject,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final TimetableRepository repository =
        ref.read(timetableRepositoryProvider);

    final Result<void> result = await repository.removeSubject(subject);

    result.fold(
      (_) => messenger.showSnackBar(
        SnackBar(
          content: Text('Removed $subject'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => repository.addSubject(subject),
          ),
        ),
      ),
      (failure) =>
          messenger.showSnackBar(SnackBar(content: Text(failure.message))),
    );
  }

  Future<void> _restoreDefaults(BuildContext context, WidgetRef ref) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Restore default subjects?'),
        content: const Text(
          'The list goes back to the standard subjects. Any you added will be '
          'removed from the list, but your existing classes keep their subjects.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;
    await ref.read(timetableRepositoryProvider).restoreDefaultSubjects();
  }
}
