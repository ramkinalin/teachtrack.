import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/day_time.dart';
import '../../../../core/utils/result.dart';
import '../../../profile/presentation/profile_form.dart';
import '../../../profile/presentation/profile_providers.dart';
import '../../../timetable/domain/entities/period.dart';
import '../../../timetable/domain/entities/timetable_entry.dart';
import '../../../timetable/domain/period_shifter.dart';
import '../../../timetable/domain/repositories/timetable_repository.dart';
import '../../../timetable/presentation/providers/timetable_providers.dart';
import '../../../timetable/presentation/widgets/entry_form_sheet.dart';
import '../widgets/onboarding_page.dart';

/// First-run setup.
///
/// Four steps, each answering one question: what is this app, who are you, when
/// does your school day start, and what do you teach. The last step drops the
/// teacher straight into the real entry form rather than describing it, so the
/// thing they learn is the thing they will actually use.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();
  final GlobalKey<ProfileFormState> _profileFormKey =
      GlobalKey<ProfileFormState>();

  static const int _pageCount = 4;

  int _page = 0;
  bool _busy = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isLast = _page == _pageCount - 1;

    return Scaffold(
      appBar: AppBar(
        title: Text('Setup · ${_page + 1} of $_pageCount'),
        actions: <Widget>[
          if (!isLast)
            TextButton(
              onPressed: _busy ? null : _finish,
              child: const Text('Skip'),
            ),
        ],
      ),
      body: Column(
        children: <Widget>[
          _ProgressBar(page: _page, pageCount: _pageCount),
          Expanded(
            child: PageView(
              controller: _pageController,
              // Driven by the buttons only: the profile step must be saved before
              // moving on, and a swipe would bypass that.
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (int index) => setState(() => _page = index),
              children: <Widget>[
                const _WelcomePage(),
                _ProfilePage(formKey: _profileFormKey),
                const _SchoolTimingsPage(),
                _FirstClassPage(onAddClass: _openEntryForm),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: <Widget>[
                  if (_page > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy ? null : _back,
                        child: const Text('Back'),
                      ),
                    ),
                  if (_page > 0) const SizedBox(width: AppSpacing.md),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: _busy ? null : (isLast ? _finish : _next),
                      child: Text(isLast ? 'Start using TeachTrack' : 'Next'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _back() => _pageController.previousPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );

  Future<void> _next() async {
    // Step 2 owns a form; it must save before the wizard advances, otherwise the
    // teacher's name is silently lost.
    if (_page == 1) {
      setState(() => _busy = true);
      final bool saved = await _profileFormKey.currentState?.submit() ?? false;
      if (!mounted) return;
      setState(() => _busy = false);
      if (!saved) return;
    }

    await _pageController.nextPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _openEntryForm() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext context) =>
          EntryFormSheet(weekday: CalendarDay.teachingWeek.first),
    );
  }

  Future<void> _finish() async {
    setState(() => _busy = true);

    final Result<void> result = await ref
        .read(profileRepositoryProvider)
        .setOnboardingCompleted(value: true);

    if (!mounted) return;
    setState(() => _busy = false);

    result.fold(
      (_) => context.goNamed(AppRoutes.todayName),
      (failure) => ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure.message))),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.page, required this.pageCount});

  final int page;
  final int pageCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < pageCount; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: i <= page
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _WelcomePage extends StatelessWidget {
  const _WelcomePage();

  @override
  Widget build(BuildContext context) {
    return const OnboardingPage(
      icon: Icons.waving_hand_outlined,
      title: 'Welcome to TeachTrack',
      body: 'Your teaching day, on your phone — and it works without internet.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _Bullet(
            icon: Icons.today_outlined,
            title: 'See today at a glance',
            body: 'Which class is on now, which is next, and how long is left.',
          ),
          _Bullet(
            icon: Icons.check_circle_outline,
            title: 'One tap to mark a class done',
            body: 'No forms, no waiting. Saved instantly on your device.',
          ),
          _Bullet(
            icon: Icons.cloud_off_outlined,
            title: 'Works on the field',
            body:
                'Playground, sports field, dead zone — everything keeps working '
                'and syncs later on its own.',
          ),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: scheme.primary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfilePage extends StatelessWidget {
  const _ProfilePage({required this.formKey});

  final GlobalKey<ProfileFormState> formKey;

  @override
  Widget build(BuildContext context) {
    return OnboardingPage(
      icon: Icons.person_outline,
      title: 'Who are you?',
      body: 'Used on your reports later. Only your name is required.',
      child: ProfileForm(
        key: formKey,
        submitLabel: 'Save',
        autofocus: true,
        // The wizard's Next button drives saving, so the form's own button would
        // be a second, confusing way to do the same thing.
        showSubmitButton: false,
      ),
    );
  }
}

class _SchoolTimingsPage extends ConsumerWidget {
  const _SchoolTimingsPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Period> periods = ref.watch(periodsProvider);
    final int? firstStart = PeriodShifter.firstStartMinute(periods);

    return OnboardingPage(
      icon: Icons.schedule_outlined,
      title: 'When does your school day start?',
      body: 'We will shift the whole period grid to match. You can fine-tune '
          'individual periods later.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          OutlinedButton.icon(
            onPressed: firstStart == null
                ? null
                : () => _pickStartTime(context, ref, periods, firstStart),
            icon: const Icon(Icons.access_time),
            label: Text(
              firstStart == null
                  ? 'No periods defined'
                  : 'First period starts at ${DayTime.format(firstStart)}',
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Your day',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final Period period in periods)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      period.label,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontStyle:
                                period.isBreak ? FontStyle.italic : null,
                          ),
                    ),
                  ),
                  Text(
                    period.timeRangeLabel,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _pickStartTime(
    BuildContext context,
    WidgetRef ref,
    List<Period> periods,
    int currentStart,
  ) async {
    // Resolved before the await: a WidgetRef used after its widget is disposed
    // throws, and a modal can outlive the page in edge cases.
    final TimetableRepository repository =
        ref.read(timetableRepositoryProvider);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: currentStart ~/ 60, minute: currentStart % 60),
      helpText: 'First period starts at',
    );
    if (picked == null) return;

    final List<Period>? shifted = PeriodShifter.shiftTo(
      periods,
      picked.hour * 60 + picked.minute,
    );

    if (shifted == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('That start time would push the school day past midnight'),
        ),
      );
      return;
    }

    final Result<void> result = await repository.replacePeriods(shifted);

    result.fold(
      (_) {},
      (failure) =>
          messenger.showSnackBar(SnackBar(content: Text(failure.message))),
    );
  }
}

class _FirstClassPage extends ConsumerWidget {
  const _FirstClassPage({required this.onAddClass});

  final Future<void> Function() onAddClass;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<TimetableEntry> entries = ref.watch(allEntriesProvider);

    return OnboardingPage(
      icon: Icons.edit_calendar_outlined,
      title: 'Add your timetable',
      body: 'Add one class per period, for each day you teach. Enter Monday '
          'first — the rest goes quickly once you have the hang of it.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          FilledButton.icon(
            onPressed: onAddClass,
            icon: const Icon(Icons.add),
            label: const Text('Add a class'),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (entries.isEmpty)
            Text(
              'You can also skip this and add classes later from the calendar '
              'icon on the home screen.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            )
          else
            Row(
              children: <Widget>[
                Icon(
                  Icons.check_circle_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    '${entries.length} '
                    '${entries.length == 1 ? 'class' : 'classes'} added. '
                    'Keep going, or finish and add the rest later.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
