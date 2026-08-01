import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/day_time.dart';
import '../../../../core/widgets/sheet_layout.dart';
import '../../domain/entities/schedule_override.dart';
import '../providers/timetable_providers.dart';

/// Add or edit one sitting within an override.
///
/// Pops the sitting, or `null` if cancelled. Deliberately does not save anything
/// itself: the editor holds the whole override in memory and validates it as one
/// aggregate, so a half-finished exam week can never reach storage.
class OverrideSlotSheet extends ConsumerStatefulWidget {
  OverrideSlotSheet({
    required this.allowedDates,
    super.key,
    this.existing,
    this.initialDate,
  }) : assert(
          allowedDates.length > 0,
          'A sitting needs at least one date it may fall on.',
        );

  /// Dates the sitting may fall on — the override's range.
  final List<DateTime> allowedDates;

  final OverrideSlot? existing;
  final DateTime? initialDate;

  static Future<OverrideSlot?> show(
    BuildContext context, {
    required List<DateTime> allowedDates,
    OverrideSlot? existing,
    DateTime? initialDate,
  }) {
    return showModalBottomSheet<OverrideSlot>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext context) => OverrideSlotSheet(
        allowedDates: allowedDates,
        existing: existing,
        initialDate: initialDate,
      ),
    );
  }

  @override
  ConsumerState<OverrideSlotSheet> createState() => _OverrideSlotSheetState();
}

class _OverrideSlotSheetState extends ConsumerState<OverrideSlotSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _title;
  late final TextEditingController _classGroup;
  late final TextEditingController _location;
  late final TextEditingController _notes;

  late DateTime _date;
  late int _startMinute;
  int? _endMinute;
  String? _subject;
  bool _isInvigilating = false;
  bool _isMySubject = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final OverrideSlot? existing = widget.existing;

    _title = TextEditingController(text: existing?.title ?? '');
    _classGroup = TextEditingController(text: existing?.classGroup ?? '');
    _location = TextEditingController(text: existing?.location ?? '');
    _notes = TextEditingController(text: existing?.notes ?? '');

    // Any date must be one the dropdown actually offers, or the field asserts.
    final DateTime candidate =
        existing?.date ?? widget.initialDate ?? widget.allowedDates.first;
    _date = widget.allowedDates.firstWhere(
      (DateTime d) => CalendarDay.isSameDay(d, candidate),
      orElse: () => widget.allowedDates.first,
    );

    _startMinute = existing?.startMinute ?? 9 * 60;
    // An existing sitting keeps its end time, including *not having one* —
    // defaulting here would silently stamp 11:00 onto a sitting deliberately left
    // open-ended. Only a new one gets a default.
    _endMinute = existing != null ? existing.endMinute : 11 * 60;
    _isInvigilating = existing?.isInvigilating ?? false;
    _isMySubject = existing?.isMySubject ?? false;

    final String? subject = existing?.subject;
    _subject = (subject != null &&
            subject.isNotEmpty &&
            ref.read(subjectsProvider).contains(subject))
        ? subject
        : null;
  }

  @override
  void dispose() {
    _title.dispose();
    _classGroup.dispose();
    _location.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<String> subjects = ref.watch(subjectsProvider);

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
                _isEditing ? 'Edit sitting' : 'Add sitting',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.lg),
              DropdownButtonFormField<DateTime>(
                initialValue: _date,
                decoration: const InputDecoration(
                  labelText: 'Date',
                  border: OutlineInputBorder(),
                ),
                items: <DropdownMenuItem<DateTime>>[
                  for (final DateTime date in widget.allowedDates)
                    DropdownMenuItem<DateTime>(
                      value: date,
                      child: Text(
                        '${CalendarDay.shortLabel(date.weekday)} '
                        '${CalendarDay.key(date)}',
                      ),
                    ),
                ],
                onChanged: (DateTime? value) =>
                    setState(() => _date = value ?? _date),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _title,
                autofocus: !_isEditing,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'What is being sat',
                  hintText: 'Mathematics paper 1',
                  border: OutlineInputBorder(),
                ),
                validator: (String? value) =>
                    (value == null || value.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final int? picked =
                            await _pickTime(context, _startMinute);
                        if (picked != null) {
                          setState(() => _startMinute = picked);
                        }
                      },
                      child: Text('Starts ${DayTime.format(_startMinute)}'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    // Long-press clears it. A sitting with no stated end is
                    // legitimate, and there would otherwise be no way back to
                    // that once a time had been picked.
                    child: GestureDetector(
                      onLongPress: () => setState(() => _endMinute = null),
                      child: OutlinedButton(
                        onPressed: () async {
                          final int initial = _endMinute ??
                              (_startMinute + 60)
                                  .clamp(0, DayTime.minutesPerDay - 1);
                          final int? picked = await _pickTime(context, initial);
                          if (picked != null) {
                            setState(() => _endMinute = picked);
                          }
                        },
                        child: Text(
                          _endMinute == null
                              ? 'No end time'
                              : 'Ends ${DayTime.format(_endMinute!)}',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
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
                  const DropdownMenuItem<String>(child: Text('None')),
                  for (final String subject in subjects)
                    DropdownMenuItem<String>(
                      value: subject,
                      child: Text(subject, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (String? value) => setState(() => _subject = value),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _location,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Hall or room (optional)',
                  hintText: 'Hall A',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              SwitchListTile.adaptive(
                value: _isInvigilating,
                contentPadding: EdgeInsets.zero,
                title: const Text('I am invigilating'),
                subtitle: const Text('Shows as duty, and can be ticked off'),
                onChanged: (bool value) =>
                    setState(() => _isInvigilating = value),
              ),
              SwitchListTile.adaptive(
                value: _isMySubject,
                contentPadding: EdgeInsets.zero,
                title: const Text('This is my subject'),
                subtitle: const Text('Marking will land with you'),
                onChanged: (bool value) => setState(() => _isMySubject = value),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _notes,
                maxLines: 3,
                minLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  hintText: 'Syllabus covered, materials allowed',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: FilledButton(
                      onPressed: _submit,
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

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final int? end = _endMinute;
    if (end != null && end <= _startMinute) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('It must end after it starts')),
      );
      return;
    }

    Navigator.of(context).pop(
      OverrideSlot(
        // A new sitting gets a fresh id; an edit keeps its own, so any session
        // already recorded against it survives.
        id: widget.existing?.id ?? const Uuid().v4(),
        date: _date,
        startMinute: _startMinute,
        endMinute: end,
        title: _title.text.trim(),
        classGroup: _classGroup.text.trim(),
        subject: _subject ?? '',
        location: _location.text.trim(),
        isInvigilating: _isInvigilating,
        isMySubject: _isMySubject,
        notes: _notes.text.trim(),
      ),
    );
  }
}
