import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';

/// Sheet for writing what was actually taught in one lesson.
///
/// Pops the new text, or `null` if the teacher backed out — so cancelling can be
/// told apart from clearing a note, which pops an empty string.
class SessionNoteSheet extends StatefulWidget {
  const SessionNoteSheet({
    required this.title,
    super.key,
    this.initialNote = '',
  });

  final String title;
  final String initialNote;

  /// Convenience wrapper: returns the entered note, or `null` on cancel.
  static Future<String?> show(
    BuildContext context, {
    required String title,
    String initialNote = '',
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext context) =>
          SessionNoteSheet(title: title, initialNote: initialNote),
    );
  }

  @override
  State<SessionNoteSheet> createState() => _SessionNoteSheetState();
}

class _SessionNoteSheetState extends State<SessionNoteSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialNote);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool hadNote = widget.initialNote.trim().isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.md,
        right: AppSpacing.md,
        top: AppSpacing.md,
        bottom: AppSpacing.md + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            hadNote ? 'Edit note' : 'Add note',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            widget.title,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLines: 4,
            minLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Finished chapter 4, set exercise 3',
              helperText: 'What you covered, homework set, anything to remember',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: <Widget>[
              if (hadNote)
                Expanded(
                  child: TextButton(
                    // Pops an empty string, which the caller treats as "clear"
                    // rather than "cancel".
                    onPressed: () => Navigator.of(context).pop(''),
                    child: const Text('Delete'),
                  ),
                ),
              if (hadNote) const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: () =>
                      Navigator.of(context).pop(_controller.text.trim()),
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
