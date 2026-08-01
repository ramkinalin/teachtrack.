import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/day_time.dart';
import '../../../../core/utils/result.dart';
import '../../../../core/widgets/sheet_layout.dart';
import '../../../profile/presentation/profile_providers.dart';
import '../../domain/entities/period.dart';
import '../../domain/entities/timetable_entry.dart';
import '../../domain/repositories/timetable_repository.dart';
import '../providers/timetable_providers.dart';

/// Add or edit a single timetable entry.
///
/// Validation is delegated to the repository rather than duplicated here, so the
/// same slot-conflict rule applies to any future caller (import, sync, tests).
class EntryFormSheet extends ConsumerStatefulWidget {
  const EntryFormSheet({required this.weekday, super.key, this.existing});

  final int weekday;
  final TimetableEntry? existing;

  @override
  ConsumerState<EntryFormSheet> createState() => _EntryFormSheetState();
}

class _EntryFormSheetState extends ConsumerState<EntryFormSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  /// Needed to push a value back into the subject field.
  ///
  /// Picking the "Add new subject" row has already committed the sentinel as the
  /// field's displayed value by the time `onChanged` runs. Rebuilding does not
  /// undo that — the dropdown only re-reads `initialValue` when it changes — so
  /// cancelling the dialog would strand the field on "+ Add new subject…" and
  /// silently drop the entry's real subject. Driving the field state directly is
  /// the only reliable way back.
  final GlobalKey<FormFieldState<String>> _subjectFieldKey =
      GlobalKey<FormFieldState<String>>();

  late final TextEditingController _classGroup;
  late final TextEditingController _room;

  late int _weekday;
  String? _periodId;
  String? _subject;
  bool _isPe = false;
  bool _saving = false;
  String? _slotError;

  /// Sentinel value for the "Add new subject" dropdown row.
  static const String _addSubjectValue = '__add_subject__';

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final TimetableEntry? existing = widget.existing;
    _classGroup = TextEditingController(text: existing?.classGroup ?? '');
    _room = TextEditingController(text: existing?.room ?? '');
    _isPe = existing?.isPhysicalEducation ?? false;

    // A DropdownButtonFormField asserts that its value appears exactly once
    // among its items. An existing entry can legitimately point at a day, period
    // or subject the pickers do not offer — a break period, one that has since
    // been deleted, or a subject removed from the list — so each is checked
    // against the selectable set here rather than blowing up when the sheet opens.
    final int candidateWeekday = existing?.weekday ?? widget.weekday;
    _weekday = CalendarDay.teachingWeek.contains(candidateWeekday)
        ? candidateWeekday
        : CalendarDay.teachingWeek.first;

    final String? candidatePeriodId = existing?.periodId;
    final bool periodIsSelectable = ref
        .read(periodsProvider)
        .any((Period p) => !p.isBreak && p.id == candidatePeriodId);
    _periodId = periodIsSelectable ? candidatePeriodId : null;

    final String? candidateSubject = existing?.subject;
    _subject = ref.read(subjectsProvider).contains(candidateSubject)
        ? candidateSubject
        : null;
  }

  @override
  void dispose() {
    _classGroup.dispose();
    _room.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<Period> periods = ref
        .watch(periodsProvider)
        .where((Period p) => !p.isBreak)
        .toList(growable: false);
    final List<String> subjects = ref.watch(subjectsProvider);

    return Padding(
      // Keeps the buttons clear of both the keyboard and the system navigation
      // bar — padding for only one leaves them half-hidden behind the other.
      padding: sheetContentPadding(context),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                _isEditing ? 'Edit class' : 'Add class',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'One entry per period. It repeats every week on this day.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: AppSpacing.lg),
              DropdownButtonFormField<int>(
                initialValue: _weekday,
                decoration: const InputDecoration(
                  labelText: 'Day',
                  border: OutlineInputBorder(),
                ),
                items: <DropdownMenuItem<int>>[
                  for (final int weekday in CalendarDay.teachingWeek)
                    DropdownMenuItem<int>(
                      value: weekday,
                      child: Text(CalendarDay.longLabel(weekday)),
                    ),
                ],
                onChanged: (int? value) => setState(() {
                  _weekday = value ?? _weekday;
                  _slotError = null;
                }),
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String>(
                initialValue: _periodId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Period',
                  border: const OutlineInputBorder(),
                  errorText: _slotError,
                ),
                items: <DropdownMenuItem<String>>[
                  for (final Period period in periods)
                    DropdownMenuItem<String>(
                      value: period.id,
                      child: Text(
                        '${period.label} · ${period.timeRangeLabel}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                validator: (String? value) =>
                    value == null ? 'Choose a period' : null,
                onChanged: (String? value) => setState(() {
                  _periodId = value;
                  _slotError = null;
                }),
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String>(
                key: _subjectFieldKey,
                initialValue: _subject,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Subject',
                  border: OutlineInputBorder(),
                ),
                items: <DropdownMenuItem<String>>[
                  for (final String subject in subjects)
                    DropdownMenuItem<String>(
                      value: subject,
                      child: Text(subject, overflow: TextOverflow.ellipsis),
                    ),
                  const DropdownMenuItem<String>(
                    value: _addSubjectValue,
                    child: Text('+ Add new subject…'),
                  ),
                ],
                validator: (String? value) =>
                    (value == null || value == _addSubjectValue)
                        ? 'Choose a subject'
                        : null,
                onChanged: _onSubjectChanged,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _classGroup,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Class',
                  hintText: '8B',
                  helperText: 'The class or section you teach in this period',
                  border: OutlineInputBorder(),
                ),
                validator: (String? value) =>
                    (value == null || value.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _room,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Room or location (optional)',
                  hintText: 'Main Field',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              SwitchListTile.adaptive(
                value: _isPe,
                onChanged: (bool value) => setState(() => _isPe = value),
                contentPadding: EdgeInsets.zero,
                title: const Text('Physical education'),
                subtitle: const Text('Enables PE tools for this class'),
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

  Future<void> _onSubjectChanged(String? value) async {
    if (value != _addSubjectValue) {
      setState(() => _subject = value);
      return;
    }

    final String? previous = _subject;
    final String? created = await _promptForNewSubject();
    if (!mounted) return;

    // Always write a real value back, even on cancel: the sentinel is currently
    // showing in the field and only didChange will clear it.
    //
    // No setState needed — the dropdown's didChange forwards to onChanged, which
    // re-enters this method with a non-sentinel value and sets _subject there.
    _subjectFieldKey.currentState?.didChange(created ?? previous);
  }

  Future<String?> _promptForNewSubject() async {
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
            decoration: const InputDecoration(
              labelText: 'Subject name',
              hintText: 'Sanskrit',
            ),
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

      if (entered == null || entered.isEmpty) return null;

      final Result<String> result =
          await ref.read(timetableRepositoryProvider).addSubject(entered);

      // The store returns the canonical spelling, so typing "maths" when
      // "Maths" exists selects the existing one instead of creating a duplicate.
      return result.valueOrNull;
    } finally {
      controller.dispose();
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _saving = true;
      _slotError = null;
    });

    final TimetableRepository repository =
        ref.read(timetableRepositoryProvider);

    final TimetableEntry entry = TimetableEntry(
      id: widget.existing?.id ?? const Uuid().v4(),
      weekday: _weekday,
      periodId: _periodId!,
      subject: _subject!,
      classGroup: _classGroup.text.trim(),
      room: _room.text.trim(),
      isPhysicalEducation: _isPe,
      notes: widget.existing?.notes ?? '',
      // Stamped from the profile so the entry has an owner from the moment it is
      // created; a school-wide view later groups by this.
      teacherId: ref.read(activeTeacherIdProvider),
    );

    final Result<void> result = await repository.upsertEntry(entry);
    if (!mounted) return;

    result.fold(
      (_) => Navigator.of(context).pop(),
      (Failure failure) {
        setState(() {
          _saving = false;
          // Slot clashes belong on the period field; anything else is a snackbar.
          _slotError =
              failure is ValidationFailure && failure.field == 'periodId'
                  ? failure.message
                  : null;
        });
        if (_slotError == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(failure.message)),
          );
        }
      },
    );
  }
}
