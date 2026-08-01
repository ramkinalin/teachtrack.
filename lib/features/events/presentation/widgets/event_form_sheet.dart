import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/day_time.dart';
import '../../../../core/utils/result.dart';
import '../../../../core/widgets/sheet_layout.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../../profile/presentation/profile_providers.dart';
import '../../../timetable/presentation/providers/timetable_providers.dart';
import '../../domain/entities/school_event.dart';
import '../../domain/event_reminder_coordinator.dart';
import '../../domain/event_reminder_planner.dart';
import '../../domain/repositories/event_repository.dart';
import '../providers/event_providers.dart';

/// Add or edit a dated event.
///
/// The fields shift with the category: a test asks for class and subject, a
/// fixture asks for opponent and venue. Same form, same validation, so a new
/// category costs almost nothing.
class EventFormSheet extends ConsumerStatefulWidget {
  const EventFormSheet({super.key, this.existing, this.initialDate});

  final SchoolEvent? existing;
  final DateTime? initialDate;

  static Future<void> show(
    BuildContext context, {
    SchoolEvent? existing,
    DateTime? initialDate,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext context) =>
          EventFormSheet(existing: existing, initialDate: initialDate),
    );
  }

  @override
  ConsumerState<EventFormSheet> createState() => _EventFormSheetState();
}

class _EventFormSheetState extends ConsumerState<EventFormSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _title;
  late final TextEditingController _classGroup;
  late final TextEditingController _location;
  late final TextEditingController _opponent;
  late final TextEditingController _notes;

  late SchoolEventCategory _category;
  late DateTime _date;
  late List<int> _reminderLeads;

  String? _subject;
  int? _startMinute;
  int? _endMinute;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final SchoolEvent? existing = widget.existing;

    _title = TextEditingController(text: existing?.title ?? '');
    _classGroup = TextEditingController(text: existing?.classGroup ?? '');
    _location = TextEditingController(text: existing?.location ?? '');
    _opponent = TextEditingController(text: existing?.opponent ?? '');
    _notes = TextEditingController(text: existing?.notes ?? '');

    _category = existing?.category ?? SchoolEventCategory.classTest;
    // Through the injected clock like every other date in the project, so the
    // sheet's default is testable with FakeClock.
    _date = CalendarDay.dateOnly(
      existing?.date ?? widget.initialDate ?? ref.read(clockProvider).now(),
    );
    // New events start with a time; an existing one keeps whatever it had,
    // including none. Defaulting to all-day was a trap: an all-day event anchors
    // its reminders at 08:00, so anything added during the day silently got no
    // reminder at all.
    _startMinute = existing != null ? existing.startMinute : 9 * 60;
    _endMinute = existing?.endMinute;
    _reminderLeads = List<int>.from(
      existing?.reminderLeadMinutes ?? _category.defaultReminderLeadMinutes,
    );

    // Guarded the same way as the timetable form: a subject removed from the
    // list must not be passed to a dropdown that no longer offers it.
    final String? candidate = existing?.subject;
    _subject = (candidate != null && candidate.isNotEmpty)
        ? (ref.read(subjectsProvider).contains(candidate) ? candidate : null)
        : null;
  }

  @override
  void dispose() {
    _title.dispose();
    _classGroup.dispose();
    _location.dispose();
    _opponent.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<String> subjects = ref.watch(subjectsProvider);
    final bool isFixture = _category.isFixture;

    return Padding(
      padding: sheetContentPadding(context),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                _isEditing ? 'Edit event' : 'Add event',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.lg),
              DropdownButtonFormField<SchoolEventCategory>(
                initialValue: _category,
                decoration: const InputDecoration(
                  labelText: 'Type',
                  border: OutlineInputBorder(),
                ),
                items: <DropdownMenuItem<SchoolEventCategory>>[
                  for (final SchoolEventCategory category
                      in SchoolEventCategory.values)
                    DropdownMenuItem<SchoolEventCategory>(
                      value: category,
                      child: Text(category.label),
                    ),
                ],
                onChanged: _onCategoryChanged,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Name',
                  hintText: isFixture ? 'Inter-house football' : 'Unit test 2',
                  border: const OutlineInputBorder(),
                ),
                validator: (String? value) =>
                    (value == null || value.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: AppSpacing.md),
              _DateField(
                date: _date,
                onPick: (DateTime picked) => setState(() => _date = picked),
              ),
              const SizedBox(height: AppSpacing.md),
              _TimeRangeField(
                startMinute: _startMinute,
                endMinute: _endMinute,
                onChanged: (int? start, int? end) => setState(() {
                  _startMinute = start;
                  _endMinute = end;
                }),
              ),
              const SizedBox(height: AppSpacing.md),
              if (isFixture) ...<Widget>[
                TextFormField(
                  controller: _opponent,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Opponent or teams (optional)',
                    hintText: "St. Xavier's",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ] else ...<Widget>[
                TextFormField(
                  controller: _classGroup,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Class (optional)',
                    hintText: '8B',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  initialValue: _subject,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Subject (optional)',
                    border: OutlineInputBorder(),
                  ),
                  items: <DropdownMenuItem<String>>[
                    // A null entry so an optional field can actually be unset
                    // again once something has been chosen.
                    const DropdownMenuItem<String>(child: Text('None')),
                    for (final String subject in subjects)
                      DropdownMenuItem<String>(
                        value: subject,
                        child: Text(subject, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (String? value) =>
                      setState(() => _subject = value),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              TextFormField(
                controller: _location,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: isFixture
                      ? 'Venue (optional)'
                      : 'Room or location (optional)',
                  hintText: isFixture ? 'Main Field' : 'R-12',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _notes,
                maxLines: 3,
                minLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  hintText: 'Syllabus, kit to bring, anything to remember',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              _ReminderPicker(
                selected: _reminderLeads,
                isAllDay: _startMinute == null,
                onChanged: (List<int> leads) =>
                    setState(() => _reminderLeads = leads),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          _saving ? null : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      child: Text(_isEditing ? 'Save' : 'Add'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onCategoryChanged(SchoolEventCategory? value) {
    if (value == null) return;
    setState(() {
      final bool remindersWereDefault = _listEquals(
        _reminderLeads,
        _category.defaultReminderLeadMinutes,
      );
      _category = value;
      // Only re-apply defaults if the teacher hadn't customised them — changing
      // the type should not silently discard a deliberate choice.
      if (remindersWereDefault) {
        _reminderLeads = List<int>.from(value.defaultReminderLeadMinutes);
      }
    });
  }

  static bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);

    final EventRepository repository = ref.read(eventRepositoryProvider);
    final bool isFixture = _category.isFixture;

    final SchoolEvent event = SchoolEvent(
      id: widget.existing?.id ?? const Uuid().v4(),
      date: _date,
      category: _category,
      title: _title.text.trim(),
      classGroup: isFixture ? '' : _classGroup.text.trim(),
      subject: isFixture ? '' : (_subject ?? ''),
      startMinute: _startMinute,
      endMinute: _endMinute,
      location: _location.text.trim(),
      opponent: isFixture ? _opponent.text.trim() : '',
      notes: _notes.text.trim(),
      reminderLeadMinutes: List<int>.unmodifiable(_reminderLeads),
      teacherId: ref.read(activeTeacherIdProvider),
    );

    final EventReminderCoordinator coordinator =
        ref.read(eventReminderCoordinatorProvider);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    final Result<void> result = await repository.upsert(event);
    if (!mounted) return;

    // Deliberately not `fold` with an async branch: that infers a Future the
    // statement then discards, so the permission request would run unobserved.
    final Failure? failure = result.failureOrNull;
    if (failure != null) {
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
      return;
    }

    Navigator.of(context).pop();

    if (!event.hasReminders) return;

    // An event whose reminder times have all passed schedules nothing. That is
    // correct — a notification for something that already started is noise — but
    // silence would leave the bell icon promising something impossible. Most
    // often this is an all-day event added later in the day: it anchors at 08:00,
    // so every lead resolves to the past.
    if (EventReminderPlanner.plan(<SchoolEvent>[event], ref.read(clockProvider).now())
        .isEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            event.isAllDay
                ? 'Saved. No reminder set — an all-day event reminds from 08:00, '
                    'which has passed. Set a time to get one.'
                : 'Saved. No reminder set — those reminder times have passed.',
          ),
          duration: const Duration(seconds: 6),
        ),
      );
      return;
    }

    // Permission is asked here rather than at launch: the prompt makes obvious
    // sense right after choosing reminders, and a teacher who never sets one is
    // never interrupted. A null count means it was refused, so say so instead of
    // leaving the bell icon promising something that will not happen.
    final int? scheduled = await coordinator.sync(requestPermission: true);
    if (scheduled != null) return;

    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'Saved, but reminders need notification permission — enable it in '
          'Android settings',
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.date, required this.onPick});

  final DateTime date;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Date',
        border: OutlineInputBorder(),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              '${CalendarDay.longLabel(date.weekday)}, ${CalendarDay.key(date)}',
            ),
          ),
          TextButton(
            onPressed: () async {
              final DateTime? picked = await showDatePicker(
                context: context,
                initialDate: date,
                // A year either side covers a school year in both directions
                // without offering an absurd range.
                firstDate: DateTime(date.year - 1),
                lastDate: DateTime(date.year + 2),
              );
              if (picked != null) onPick(CalendarDay.dateOnly(picked));
            },
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }
}

class _TimeRangeField extends StatelessWidget {
  const _TimeRangeField({
    required this.startMinute,
    required this.endMinute,
    required this.onChanged,
  });

  final int? startMinute;
  final int? endMinute;
  final void Function(int? start, int? end) onChanged;

  @override
  Widget build(BuildContext context) {
    final int? start = startMinute;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SwitchListTile.adaptive(
          value: start != null,
          contentPadding: EdgeInsets.zero,
          title: const Text('Set a time'),
          subtitle: Text(start == null ? 'All day' : 'Reminders use this time'),
          // Turning the time off must clear the end time too, or validation
          // would reject an end without a start.
          onChanged: (bool value) =>
              onChanged(value ? 9 * 60 : null, value ? endMinute : null),
        ),
        if (start != null)
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final int? picked = await _pickTime(context, start);
                    if (picked != null) onChanged(picked, endMinute);
                  },
                  child: Text('Starts ${DayTime.format(start)}'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    // Clamped: a start near midnight would otherwise open the
                    // picker at an invalid 24:00.
                    final int initial = endMinute ??
                        (start + 60).clamp(0, DayTime.minutesPerDay - 1);
                    final int? picked = await _pickTime(context, initial);
                    if (picked != null) onChanged(start, picked);
                  },
                  child: Text(
                    endMinute == null
                        ? 'End time'
                        : 'Ends ${DayTime.format(endMinute!)}',
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  static Future<int?> _pickTime(BuildContext context, int initialMinute) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: initialMinute ~/ 60,
        minute: initialMinute % 60,
      ),
    );
    return picked == null ? null : picked.hour * 60 + picked.minute;
  }
}

class _ReminderPicker extends StatelessWidget {
  const _ReminderPicker({
    required this.selected,
    required this.onChanged,
    this.isAllDay = false,
  });

  final List<int> selected;
  final ValueChanged<List<int>> onChanged;

  /// Changes what the leads are measured from, which is worth saying out loud.
  final bool isAllDay;

  /// Offered lead times, in minutes.
  static const Map<int, String> _options = <int, String>{
    0: 'At the time',
    30: '30 min before',
    60: '1 hour before',
    120: '2 hours before',
    1440: '1 day before',
    2880: '2 days before',
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Remind me', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        Text(
          isAllDay
              ? 'Counted back from 08:00 on the day, since this event has no '
                  'time. Reminders may arrive a minute or two late.'
              : 'Counted back from the start time. Reminders may arrive a minute '
                  'or two late — Android batches them to save battery.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: <Widget>[
            for (final MapEntry<int, String> option in _options.entries)
              FilterChip(
                label: Text(option.value),
                selected: selected.contains(option.key),
                onSelected: (bool on) {
                  final List<int> next = List<int>.from(selected);
                  if (on) {
                    next.add(option.key);
                  } else {
                    next.remove(option.key);
                  }
                  next.sort((int a, int b) => b.compareTo(a));
                  onChanged(next);
                },
              ),
          ],
        ),
      ],
    );
  }
}
