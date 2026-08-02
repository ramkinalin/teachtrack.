import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/utils/day_time.dart';
import '../../../../core/utils/result.dart';
import '../../../../core/widgets/sheet_layout.dart';
import '../../../backup/domain/backup_payload.dart';
import '../../../backup/domain/backup_repository.dart';
import '../../../backup/presentation/backup_providers.dart';
import '../../../events/presentation/providers/event_providers.dart';
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
            leading: const Icon(Icons.schedule_outlined),
            title: const Text('School timings'),
            subtitle: Text(
              '${ref.watch(periodsProvider).length} periods · tap to change '
              'lengths',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.pushNamed(AppRoutes.periodsName),
          ),
          ListTile(
            leading: const Icon(Icons.event_note_outlined),
            title: const Text('Exams and holidays'),
            subtitle: const Text('Days when the normal timetable steps aside'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.pushNamed(AppRoutes.overridesName),
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
          const _SectionHeader('Reminders'),
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('Scheduled reminders'),
            subtitle: Text(
              ref.watch(pendingReminderCountProvider).maybeWhen(
                    data: (int count) => count == 0
                        ? 'None waiting'
                        : '$count waiting on this phone',
                    orElse: () => 'Checking…',
                  ),
            ),
            trailing: const Icon(Icons.refresh_rounded),
            onTap: () => _resyncReminders(context, ref),
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
          const _SectionHeader('Backup'),
          ListTile(
            leading: const Icon(Icons.upload_file_outlined),
            title: const Text('Export a backup'),
            subtitle: const Text(
              'Save or send a file holding everything on this phone',
            ),
            onTap: () => _export(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.restore_page_outlined),
            title: const Text('Restore from a backup'),
            subtitle: const Text('Replaces what is on this phone'),
            onTap: () => _restore(context, ref),
          ),
          // Said out loud because Auto Backup is invisible: a teacher who assumes
          // it is protecting them, when their phone has Google backup switched
          // off, would find out at the worst possible moment.
          Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.md,
              right: AppSpacing.md,
              bottom: AppSpacing.sm,
            ),
            child: Text(
              'Android also backs this app up to your Google account and restores '
              'it on a new phone, if you have backup switched on in your phone '
              'settings. You cannot see or trigger that — the export file above '
              'is the one you control.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
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

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final BackupRepository repository = ref.read(backupRepositoryProvider);
    final BackupPayload payload = repository.snapshot();

    final Result<void> result = await ref.read(backupFileServiceProvider).share(
          json: payload.encode(),
          fileName: repository.suggestedFileName(),
        );

    result.fold(
      (_) {},
      (failure) =>
          messenger.showSnackBar(SnackBar(content: Text(failure.message))),
    );
  }

  /// Picks a file, shows what is in it, and only then touches anything.
  ///
  /// The confirmation names the contents on purpose: a restore is destructive and
  /// irreversible, and this is the last moment a teacher can tell that they picked
  /// the wrong file.
  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final BackupRepository repository = ref.read(backupRepositoryProvider);

    final Result<String?> picked =
        await ref.read(backupFileServiceProvider).pickJson();
    if (!context.mounted) return;

    final Failure? pickFailure = picked.failureOrNull;
    if (pickFailure != null) {
      messenger.showSnackBar(SnackBar(content: Text(pickFailure.message)));
      return;
    }

    final String? json = picked.valueOrNull;
    if (json == null) return; // Cancelled.

    final BackupPayload payload;
    try {
      payload = BackupPayload.decode(json);
    } on BackupFormatException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
      return;
    }

    if (!context.mounted) return;

    final RestoreMode? mode = await showDialog<RestoreMode>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Restore this backup?'),
        content: Text(
          'From ${CalendarDay.key(payload.exportedAt)}, holding '
          '${payload.contentsSummary}.\n\n'
          'Replace removes what is on this phone first. Merge keeps what is here '
          'and adds anything missing.\n\n'
          'Replace cannot be undone.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(RestoreMode.merge),
            child: const Text('Merge'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(RestoreMode.replace),
            child: const Text('Replace'),
          ),
        ],
      ),
    );

    if (mode == null || !context.mounted) return;

    final Result<RestoreSummary> result =
        await repository.restore(payload, mode: mode);

    result.fold(
      (RestoreSummary summary) => messenger.showSnackBar(
        SnackBar(
          content: Text(summary.summary),
          duration: const Duration(seconds: 6),
        ),
      ),
      (failure) =>
          messenger.showSnackBar(SnackBar(content: Text(failure.message))),
    );
  }

  /// Re-registers every reminder, asking for permission if it isn't granted.
  ///
  /// The one place a teacher can find out *why* nothing is arriving, which on
  /// Android is nearly always a denied notification permission.
  Future<void> _resyncReminders(BuildContext context, WidgetRef ref) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final int? count = await ref
        .read(eventReminderCoordinatorProvider)
        .sync(requestPermission: true);

    ref.invalidate(pendingReminderCountProvider);

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          count == null
              ? 'Reminders need notification permission — enable it in Android '
                  'settings'
              : count == 0
                  ? 'Nothing to remind you about yet'
                  : '$count reminders scheduled',
        ),
      ),
    );
  }

  Future<void> _editProfile(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext sheetContext) => Padding(
        padding: sheetContentPadding(sheetContext),
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
