import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/day_time.dart';
import '../../../../core/utils/result.dart';
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

  late final TextEditingController _subject;
  late final TextEditingController _classGroup;
  late final TextEditingController _room;

  late int _weekday;
  String? _periodId;
  bool _isPe = false;
  bool _saving = false;
  String? _slotError;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final TimetableEntry? existing = widget.existing;
    _subject = TextEditingController(text: existing?.subject ?? '');
    _classGroup = TextEditingController(text: existing?.classGroup ?? '');
    _room = TextEditingController(text: existing?.room ?? '');
    _isPe = existing?.isPhysicalEducation ?? false;

    // A DropdownButtonFormField asserts that its value appears exactly once
    // among its items. An existing entry can legitimately point at a day or a
    // period the pickers do not offer — a break period, or one that has since
    // been deleted — so both are validated against the selectable sets here
    // rather than blowing up when the sheet opens.
    final int candidateWeekday = existing?.weekday ?? widget.weekday;
    _weekday = CalendarDay.teachingWeek.contains(candidateWeekday)
        ? candidateWeekday
        : CalendarDay.teachingWeek.first;

    final String? candidatePeriodId = existing?.periodId;
    final bool periodIsSelectable = ref
        .read(periodsProvider)
        .any((Period p) => !p.isBreak && p.id == candidatePeriodId);
    _periodId = periodIsSelectable ? candidatePeriodId : null;
  }

  @override
  void dispose() {
    _subject.dispose();
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

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.md,
        right: AppSpacing.md,
        top: AppSpacing.md,
        // Keeps the save button above the keyboard on small phones.
        bottom: AppSpacing.md + MediaQuery.viewInsetsOf(context).bottom,
      ),
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
              TextFormField(
                controller: _subject,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Subject',
                  border: OutlineInputBorder(),
                ),
                validator: _required,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _classGroup,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Class',
                  hintText: '8B',
                  border: OutlineInputBorder(),
                ),
                validator: _required,
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

  static String? _required(String? value) =>
      (value == null || value.trim().isEmpty) ? 'Required' : null;

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
      subject: _subject.text.trim(),
      classGroup: _classGroup.text.trim(),
      room: _room.text.trim(),
      isPhysicalEducation: _isPe,
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
