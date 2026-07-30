import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failures.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/result.dart';
import '../domain/profile_repository.dart';
import '../domain/teacher_profile.dart';
import 'profile_providers.dart';

/// Reusable profile fields, shared by the setup wizard and the settings screen.
///
/// Owns its own save logic so both callers behave identically; they differ only
/// in the label on the button and what happens afterwards.
class ProfileForm extends ConsumerStatefulWidget {
  const ProfileForm({
    required this.submitLabel,
    super.key,
    this.onSaved,
    this.autofocus = false,
    this.showSubmitButton = true,
  });

  final String submitLabel;
  final ValueChanged<TeacherProfile>? onSaved;
  final bool autofocus;

  /// Set false when a parent drives saving through [ProfileFormState.submit] —
  /// the setup wizard does this from its own Next button.
  final bool showSubmitButton;

  @override
  ConsumerState<ProfileForm> createState() => ProfileFormState();
}

class ProfileFormState extends ConsumerState<ProfileForm> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _staffId;
  late final TextEditingController _school;
  late final TextEditingController _classTeacherOf;

  bool _isClassTeacher = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final TeacherProfile? existing = ref.read(profileProvider).profile;
    _name = TextEditingController(text: existing?.fullName ?? '');
    _staffId = TextEditingController(text: existing?.staffId ?? '');
    _school = TextEditingController(text: existing?.schoolName ?? '');
    _classTeacherOf =
        TextEditingController(text: existing?.classTeacherOf ?? '');
    _isClassTeacher = existing?.isClassTeacher ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _staffId.dispose();
    _school.dispose();
    _classTeacherOf.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextFormField(
            controller: _name,
            autofocus: widget.autofocus,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Your name',
              hintText: 'N. Ramakrishnan',
              border: OutlineInputBorder(),
            ),
            validator: (String? value) =>
                (value == null || value.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _school,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'School (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _staffId,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Staff ID (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SwitchListTile.adaptive(
            value: _isClassTeacher,
            contentPadding: EdgeInsets.zero,
            title: const Text('I am a class teacher'),
            subtitle: const Text('Adds your section to reports later'),
            onChanged: (bool value) => setState(() {
              _isClassTeacher = value;
              if (!value) _classTeacherOf.clear();
            }),
          ),
          if (_isClassTeacher) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _classTeacherOf,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Class teacher of',
                hintText: '8B',
                border: OutlineInputBorder(),
              ),
              validator: (String? value) {
                if (!_isClassTeacher) return null;
                return (value == null || value.trim().isEmpty)
                    ? 'Enter your section, e.g. 8B'
                    : null;
              },
            ),
          ],
          if (widget.showSubmitButton) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: _saving ? null : submit,
              child: Text(widget.submitLabel),
            ),
          ],
        ],
      ),
    );
  }

  /// Exposed so a parent (the wizard) can trigger saving from its own button.
  Future<bool> submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return false;

    setState(() => _saving = true);

    final ProfileRepository repository = ref.read(profileRepositoryProvider);
    final Result<TeacherProfile> result = await repository.saveProfile(
      fullName: _name.text,
      staffId: _staffId.text,
      schoolName: _school.text,
      classTeacherOf: _isClassTeacher ? _classTeacherOf.text : '',
    );

    if (!mounted) return false;
    setState(() => _saving = false);

    return result.fold(
      (TeacherProfile saved) {
        widget.onSaved?.call(saved);
        return true;
      },
      (Failure failure) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failure.message)));
        return false;
      },
    );
  }
}
