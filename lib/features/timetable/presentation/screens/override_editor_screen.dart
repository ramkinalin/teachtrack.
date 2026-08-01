import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/day_time.dart';
import '../../../../core/utils/result.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../../profile/presentation/profile_providers.dart';
import '../../domain/entities/schedule_override.dart';
import '../../domain/repositories/override_repository.dart';
import '../providers/timetable_providers.dart';
import '../widgets/override_slot_sheet.dart';

/// Create or edit one override — an exam week, a holiday, a special day.
///
/// Holds the whole thing in memory and saves once, so validation runs against the
/// complete aggregate. An exam week half-entered is not a valid exam week, and
/// incremental saving would let one reach storage and then the day view.
class OverrideEditorScreen extends ConsumerStatefulWidget {
  const OverrideEditorScreen({super.key, this.existing});

  final ScheduleOverride? existing;

  @override
  ConsumerState<OverrideEditorScreen> createState() =>
      _OverrideEditorScreenState();
}

class _OverrideEditorScreenState extends ConsumerState<OverrideEditorScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;

  late ScheduleOverrideKind _kind;
  late DateTime _startDate;
  late DateTime _endDate;
  late List<OverrideSlot> _slots;

  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final ScheduleOverride? existing = widget.existing;
    final DateTime today =
        CalendarDay.dateOnly(ref.read(clockProvider).now());

    _name = TextEditingController(text: existing?.name ?? '');
    _kind = existing?.kind ?? ScheduleOverrideKind.exam;
    _startDate = existing?.startDate ?? today;
    _endDate = existing?.endDate ??
        DateTime(today.year, today.month, today.day + 4);
    _slots = List<OverrideSlot>.from(existing?.slots ?? <OverrideSlot>[]);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// The working override, as it would be saved right now.
  ScheduleOverride get _draft => ScheduleOverride(
        id: widget.existing?.id ?? _newId,
        name: _name.text.trim(),
        kind: _kind,
        startDate: _startDate,
        endDate: _endDate,
        // A holiday hides the sittings section, so any left over from an earlier
        // choice of type would be invisible — and validation would then refuse to
        // save, pointing at a list the teacher cannot see. They are kept in
        // `_slots` so switching the type back restores them.
        slots: _kind.allowsSlots ? _slots : const <OverrideSlot>[],
        notes: widget.existing?.notes ?? '',
        teacherId: ref.read(activeTeacherIdProvider),
      );

  late final String _newId = const Uuid().v4();

  @override
  Widget build(BuildContext context) {
    final bool allowsSlots = _kind.allowsSlots;
    final List<DateTime> dates = _draft.dates;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit schedule' : 'New schedule'),
        actions: <Widget>[
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: <Widget>[
            TextFormField(
              controller: _name,
              autofocus: !_isEditing,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'Half-yearly exams',
                border: OutlineInputBorder(),
              ),
              validator: (String? value) =>
                  (value == null || value.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<ScheduleOverrideKind>(
              initialValue: _kind,
              decoration: const InputDecoration(
                labelText: 'Type',
                border: OutlineInputBorder(),
              ),
              items: <DropdownMenuItem<ScheduleOverrideKind>>[
                for (final ScheduleOverrideKind kind
                    in ScheduleOverrideKind.values)
                  DropdownMenuItem<ScheduleOverrideKind>(
                    value: kind,
                    child: Text(kind.label),
                  ),
              ],
              onChanged: (ScheduleOverrideKind? value) =>
                  setState(() => _kind = value ?? _kind),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              _kind == ScheduleOverrideKind.holiday
                  ? 'Your normal timetable is hidden on these days and nothing '
                      'is shown in its place.'
                  : 'Your normal timetable is replaced on these days by the '
                      'sittings you list below.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: AppSpacing.md),
            _DateRangeField(
              startDate: _startDate,
              endDate: _endDate,
              onChanged: (DateTime start, DateTime end) => setState(() {
                _startDate = start;
                _endDate = end;
                // Sittings left outside the new range would fail validation with
                // an error pointing at a list the teacher cannot see, so drop
                // them here and say so.
                final int before = _slots.length;
                _slots = _slots
                    .where((OverrideSlot s) => _covers(s.date, start, end))
                    .toList();
                final int dropped = before - _slots.length;
                if (dropped > 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '$dropped sitting${dropped == 1 ? '' : 's'} removed — '
                        'outside the new dates',
                      ),
                    ),
                  );
                }
              }),
            ),
            if (allowsSlots) ...<Widget>[
              const SizedBox(height: AppSpacing.xl),
              Text(
                'Sittings',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final DateTime date in dates)
                _DaySection(
                  date: date,
                  slots: _draft.slotsOn(date),
                  otherDates: dates
                      .where((DateTime d) => !CalendarDay.isSameDay(d, date))
                      .toList(growable: false),
                  onAdd: () => _addSlot(date, dates),
                  onEdit: (OverrideSlot slot) => _editSlot(slot, dates),
                  onDelete: (OverrideSlot slot) => setState(
                    () => _slots = _slots
                        .where((OverrideSlot s) => s.id != slot.id)
                        .toList(),
                  ),
                  onCopyTo: (DateTime target) => _copyDay(date, target),
                ),
            ],
            const SizedBox(height: AppSpacing.xxl),
          ],
        ),
      ),
    );
  }

  static bool _covers(DateTime date, DateTime start, DateTime end) {
    final DateTime day = CalendarDay.dateOnly(date);
    return !day.isBefore(start) && !day.isAfter(end);
  }

  Future<void> _addSlot(DateTime date, List<DateTime> dates) async {
    final OverrideSlot? slot = await OverrideSlotSheet.show(
      context,
      allowedDates: dates,
      initialDate: date,
    );
    if (slot == null) return;
    setState(() => _slots = <OverrideSlot>[..._slots, slot]);
  }

  Future<void> _editSlot(OverrideSlot slot, List<DateTime> dates) async {
    final OverrideSlot? edited = await OverrideSlotSheet.show(
      context,
      allowedDates: dates,
      existing: slot,
    );
    if (edited == null) return;
    setState(() {
      _slots = _slots
          .map((OverrideSlot s) => s.id == slot.id ? edited : s)
          .toList();
    });
  }

  void _copyDay(DateTime from, DateTime to) {
    final int before = _slots.length;
    final List<OverrideSlot> next = _draft.slotsWithDayCopied(
      from: from,
      to: to,
      idFor: (OverrideSlot _) => const Uuid().v4(),
    );

    setState(() => _slots = List<OverrideSlot>.from(next));

    final int added = next.length - before;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added == 0
              ? 'Nothing to copy'
              : 'Copied $added sitting${added == 1 ? '' : 's'} to '
                  '${CalendarDay.shortLabel(to.weekday)} '
                  '${CalendarDay.key(to)}',
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);

    final OverrideRepository repository = ref.read(overrideRepositoryProvider);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final Result<void> result = await repository.upsert(_draft);

    if (!mounted) return;

    final Failure? failure = result.failureOrNull;
    if (failure == null) {
      Navigator.of(context).pop();
      return;
    }

    setState(() => _saving = false);
    messenger.showSnackBar(SnackBar(content: Text(failure.message)));
  }
}

class _DateRangeField extends StatelessWidget {
  const _DateRangeField({
    required this.startDate,
    required this.endDate,
    required this.onChanged,
  });

  final DateTime startDate;
  final DateTime endDate;
  final void Function(DateTime start, DateTime end) onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Dates',
        border: OutlineInputBorder(),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              CalendarDay.isSameDay(startDate, endDate)
                  ? '${CalendarDay.shortLabel(startDate.weekday)} '
                      '${CalendarDay.key(startDate)}'
                  : '${CalendarDay.key(startDate)} – '
                      '${CalendarDay.key(endDate)}',
            ),
          ),
          TextButton(
            onPressed: () async {
              final DateTimeRange? picked = await showDateRangePicker(
                context: context,
                initialDateRange:
                    DateTimeRange(start: startDate, end: endDate),
                firstDate: DateTime(startDate.year - 1),
                lastDate: DateTime(startDate.year + 2),
              );
              if (picked != null) {
                onChanged(
                  CalendarDay.dateOnly(picked.start),
                  CalendarDay.dateOnly(picked.end),
                );
              }
            },
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }
}

/// One date's sittings, with the actions that belong to that day.
class _DaySection extends StatelessWidget {
  const _DaySection({
    required this.date,
    required this.slots,
    required this.otherDates,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onCopyTo,
  });

  final DateTime date;
  final List<OverrideSlot> slots;
  final List<DateTime> otherDates;
  final VoidCallback onAdd;
  final ValueChanged<OverrideSlot> onEdit;
  final ValueChanged<OverrideSlot> onDelete;
  final ValueChanged<DateTime> onCopyTo;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    '${CalendarDay.longLabel(date.weekday)} '
                    '${CalendarDay.key(date)}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (slots.isNotEmpty && otherDates.isNotEmpty)
                  PopupMenuButton<DateTime>(
                    tooltip: 'Copy this day to',
                    icon: const Icon(Icons.copy_all_outlined),
                    onSelected: onCopyTo,
                    itemBuilder: (BuildContext context) =>
                        <PopupMenuEntry<DateTime>>[
                      for (final DateTime other in otherDates)
                        PopupMenuItem<DateTime>(
                          value: other,
                          child: Text(
                            'Copy to ${CalendarDay.shortLabel(other.weekday)} '
                            '${CalendarDay.key(other)}',
                          ),
                        ),
                    ],
                  ),
                IconButton(
                  tooltip: 'Add a sitting',
                  icon: const Icon(Icons.add),
                  onPressed: onAdd,
                ),
              ],
            ),
            if (slots.isEmpty)
              Padding(
                padding: const EdgeInsets.only(
                  left: AppSpacing.sm,
                  bottom: AppSpacing.sm,
                ),
                child: Text(
                  'Nothing — this day will show as free',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              )
            else
              for (final OverrideSlot slot in slots)
                ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                  title: Text(slot.title),
                  subtitle: Text(_slotSubtitle(slot)),
                  onTap: () => onEdit(slot),
                  trailing: IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => onDelete(slot),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  static String _slotSubtitle(OverrideSlot slot) {
    final List<String> parts = <String>[
      slot.timeRangeLabel,
      if (slot.classGroup.isNotEmpty) slot.classGroup,
      if (slot.subject.isNotEmpty) slot.subject,
      if (slot.location.isNotEmpty) slot.location,
      if (slot.isInvigilating) 'On duty',
      if (slot.isMySubject) 'Your subject',
    ];
    return parts.join(' · ');
  }
}
