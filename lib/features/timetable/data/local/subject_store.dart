import 'package:hive_ce/hive.dart';

import '../../../../core/constants/hive_boxes.dart';

/// The teacher's subject list, used to populate the entry form dropdown.
///
/// Deliberately a list of names rather than a `Subject` entity with ids: a
/// timetable entry stores its subject as text, so the list is an input aid, not a
/// foreign key. That means renaming or deleting a subject can never orphan an
/// existing class, and no migration is needed for entries created before this
/// list existed.
class SubjectStore {
  SubjectStore({required Box<dynamic> settingsBox}) : _settings = settingsBox;

  final Box<dynamic> _settings;

  /// Sensible defaults for an Indian school; the teacher can add or remove any.
  static const List<String> defaults = <String>[
    'Mathematics',
    'Science',
    'Physics',
    'Chemistry',
    'Biology',
    'English',
    'Hindi',
    'Social Science',
    'History',
    'Geography',
    'Civics',
    'Computer Science',
    'Physical Education',
    'Games',
    'Art',
    'Music',
    'Library',
    'Moral Science',
  ];

  /// Alphabetically ordered so a long list stays scannable.
  List<String> subjects() {
    final Object? raw = _settings.get(SettingsKeys.subjects);
    if (raw is! List) return List<String>.unmodifiable(defaults);

    final List<String> stored = raw.whereType<String>().toList()
      ..sort((String a, String b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return stored.isEmpty
        ? List<String>.unmodifiable(defaults)
        : List<String>.unmodifiable(stored);
  }

  /// Writes the default list if nothing has been stored yet, so the first edit
  /// does not silently discard the defaults.
  Future<void> seedIfEmpty() async {
    if (_settings.get(SettingsKeys.subjects) is List) return;
    await _settings.put(SettingsKeys.subjects, defaults.toList());
  }

  /// Adds [name], ignoring case-insensitive duplicates and blanks.
  ///
  /// Returns the canonical stored name — the existing spelling when a
  /// case-variant already exists, so "maths" cannot create a second entry
  /// alongside "Maths".
  Future<String?> add(String name) async {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) return null;

    final List<String> current = subjects().toList();
    for (final String existing in current) {
      if (existing.toLowerCase() == trimmed.toLowerCase()) return existing;
    }

    current.add(trimmed);
    await _settings.put(SettingsKeys.subjects, current);
    return trimmed;
  }

  /// Removes [name] if present. Existing timetable entries keep their subject
  /// text, since the list is not a foreign key.
  ///
  /// Returns false when the removal was refused. The last subject cannot be
  /// removed: [subjects] treats an empty stored list as "nothing stored yet" and
  /// falls back to the defaults, so emptying the list would resurrect all of them
  /// and quietly undo every earlier deletion.
  Future<bool> remove(String name) async {
    final List<String> current = subjects()
        .where((String s) => s.toLowerCase() != name.trim().toLowerCase())
        .toList();

    if (current.isEmpty) return false;
    if (current.length == subjects().length) return false;

    await _settings.put(SettingsKeys.subjects, current);
    return true;
  }

  Future<void> restoreDefaults() =>
      _settings.put(SettingsKeys.subjects, defaults.toList());

  Stream<void> watchChanges() => _settings
      .watch(key: SettingsKeys.subjects)
      .map((BoxEvent _) {});
}
