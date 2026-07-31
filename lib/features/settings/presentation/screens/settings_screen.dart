import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/result.dart';
import '../../../profile/presentation/profile_form.dart';
import '../../../profile/presentation/profile_providers.dart';
import '../../../timetable/data/local/timetable_seed.dart';
import '../../../timetable/domain/repositories/timetable_repository.dart';
import '../../../timetable/presentation/providers/timetable_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ProfileState profile = ref.watch(profileProvider);
    final int subjectCount = ref.watch(subjectsProvider).length;
    final int entryCount = ref.watch(allEntriesProvider).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: <Widget>[
          const _SectionHeader('You'),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(profile.profile?.fullName ?? 'Set up your profile'),
            subtitle: Text(
              profile.profile?.displaySubtitle ?? 'Name, school, class teacher',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _editProfile(context),
          ),
          const Divider(),
          const _SectionHeader('Timetable'),
          ListTile(
            leading: const Icon(Icons.edit_calendar_outlined),
            title: const Text('Edit timetable'),
            subtitle: Text(
              entryCount == 0
                  ? 'No classes yet'
                  : '$entryCount ${entryCount == 1 ? 'class' : 'classes'}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.pushNamed(AppRoutes.timetableName),
          ),
          ListTile(
            leading: const Icon(Icons.event_outlined),
            title: const Text('Events'),
            subtitle: const Text('Tests, matches, tournaments and duties'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.pushNamed(AppRoutes.eventsName),
          ),
          ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: const Text('Subjects'),
            subtitle: Text('$subjectCount in the dropdown'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.pushNamed(AppRoutes.subjectsName),
          ),
          const Divider(),
          const _SectionHeader('Sync'),
          ListTile(
            leading: const Icon(Icons.cloud_sync_outlined),
            title: const Text('Sync diagnostics'),
            subtitle: const Text('Queued changes and what needs attention'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.pushNamed(AppRoutes.diagnosticsName),
          ),
          const Divider(),
          const _SectionHeader('Testing and reset'),
          ListTile(
            leading: const Icon(Icons.auto_awesome_outlined),
            title: const Text('Load sample timetable'),
            subtitle: const Text('Fills a demo week so you can try the app'),
            onTap: () => _loadSample(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.restart_alt_outlined),
            title: const Text('Run setup again'),
            subtitle: const Text('Walk through the introduction once more'),
            onTap: () => _rerunSetup(context, ref),
          ),
          ListTile(
            leading: Icon(
              Icons.delete_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              'Clear all data',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            subtitle: const Text('Removes your timetable and marked classes'),
            onTap: () => _clearAll(context, ref),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  Future<void> _editProfile(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.md,
          right: AppSpacing.md,
          top: AppSpacing.md,
          bottom:
              AppSpacing.md + MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Your details',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.lg),
              ProfileForm(
                submitLabel: 'Save',
                onSaved: (_) => Navigator.of(sheetContext).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadSample(BuildContext context, WidgetRef ref) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final TimetableRepository repository =
        ref.read(timetableRepositoryProvider);

    final int added = await TimetableSeed.loadSampleWeek(
      local: ref.read(timetableLocalDataSourceProvider),
      upsert: repository.upsertEntry,
      teacherId: ref.read(activeTeacherIdProvider),
    );

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          added == 0
              ? 'Sample classes are already loaded'
              : 'Added $added sample classes',
        ),
      ),
    );
  }

  Future<void> _rerunSetup(BuildContext context, WidgetRef ref) async {
    final Result<void> result = await ref
        .read(profileRepositoryProvider)
        .setOnboardingCompleted(value: false);

    if (!context.mounted) return;

    result.fold(
      (_) => context.goNamed(AppRoutes.onboardingName),
      (failure) => ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure.message))),
    );
  }

  Future<void> _clearAll(BuildContext context, WidgetRef ref) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Clear all data?'),
        content: const Text(
          'Your timetable and marked classes will be removed from this device. '
          'Your profile, school timings and subject list are kept.\n\n'
          'This cannot be undone.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final Result<int> result =
        await ref.read(timetableRepositoryProvider).clearAllData();

    result.fold(
      (int removed) => messenger.showSnackBar(
        SnackBar(
          content: Text(
            removed == 0 ? 'Nothing to clear' : 'Removed $removed records',
          ),
        ),
      ),
      (failure) =>
          messenger.showSnackBar(SnackBar(content: Text(failure.message))),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.md,
        right: AppSpacing.md,
        top: AppSpacing.lg,
        bottom: AppSpacing.sm,
      ),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
